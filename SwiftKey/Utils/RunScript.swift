import Dispatch
import Foundation
import os

private let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "RunScript")
let sharedEnv = ProcessEnv.shared

enum ScriptError: Error {
    case emptyCommand
    case dangerousCommand(String)
    case executionFailed(Int32, String)
    case invalidShell
    
    var localizedDescription: String {
        switch self {
        case .emptyCommand:
            return "Empty command provided"
        case .dangerousCommand(let cmd):
            return "Potentially dangerous command rejected: \(cmd)"
        case .executionFailed(let status, let message):
            return "Command failed with status \(status): \(message)"
        case .invalidShell:
            return "Shell executable not found"
        }
    }
}

func getEnvExportString(env: [String: String]) -> String {
    let dict = sharedEnv.systemEnvStr.merging(env) { current, _ in current }
    return "export \(dict.map { "\($0.key)='\($0.value)'" }.joined(separator: " "))"
}

@discardableResult func runScript(
    to command: String,
    args: [String] = [],
    process: Process = Process(),
    env: [String: String] = [:],
    runInBash: Bool = true,
    streamOutput: Bool = false,
    onOutputUpdate: @escaping (String?) -> Void = { _ in }
) throws
    -> (out: String, err: String?)
{
    // Pre-execution validation
    let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

    // Ensure command is not empty
    guard !trimmedCommand.isEmpty else {
        logger.error("Empty command provided")
        throw ScriptError.emptyCommand
    }

    // Runtime security check - redundant with config-time check but provides defense in depth
    let blacklistedPrefixes = ["rm -rf /", "sudo ", "> /", ">> /", "mkfs", "dd if="]
    for prefix in blacklistedPrefixes {
        if trimmedCommand.hasPrefix(prefix) || trimmedCommand.contains(" " + prefix) {
            logger.error("Potentially dangerous command rejected: \(trimmedCommand)")
            throw ScriptError.dangerousCommand(trimmedCommand)
        }
    }

    // Set up execution environment
    let swiftbarEnv = sharedEnv.systemEnvStr.merging(env) { current, _ in current }
    process.environment = swiftbarEnv.merging(ProcessInfo.processInfo.environment) { current, _ in current }

    // Execute command with enhanced error handling
    return try process.launchScript(
        with: trimmedCommand,
        args: args,
        runInBash: runInBash,
        streamOutput: streamOutput,
        onOutputUpdate: onOutputUpdate
    )
}

// Code below is adapted from https://github.com/JohnSundell/ShellOut

/// Error type thrown by the `shellOut()` function, in case the given command failed
public struct ShellOutError: Swift.Error, CustomStringConvertible {
    /// The termination status of the command that was run
    public let terminationStatus: Int32
    /// The error message as a UTF8 string, as returned through `STDERR`
    public var message: String { errorData.shellOutput() }
    /// The raw error buffer data, as returned through `STDERR`
    public let errorData: Data
    /// The raw output buffer data, as retuned through `STDOUT`
    public let outputData: Data
    /// The output of the command as a UTF8 string, as returned through `STDOUT`
    public var output: String { outputData.shellOutput() }
    
    /// A human-readable description of the error
    public var description: String {
        let errorMessage = message.isEmpty ? "Unknown error" : message
        return "Command failed with status \(terminationStatus): \(errorMessage)"
    }
    
    /// Convert this error to a ScriptError for consistent error handling
    func toScriptError() -> ScriptError {
        return .executionFailed(terminationStatus, message)
    }
}

// MARK: - Private

private extension Process {
    @discardableResult func launchScript(
        with script: String,
        args: [String],
        runInBash: Bool = true,
        streamOutput: Bool,
        onOutputUpdate: @escaping (String?) -> Void
    ) throws -> (out: String, err: String?) {
        let shell = "/bin/zsh"
        executableURL = URL(fileURLWithPath: shell)
        arguments = ["-l", "-c", "\(script.escaped()) \(args.joined(separator: " "))"]

        guard let executableURL = executableURL, FileManager.default.fileExists(atPath: executableURL.path) else {
            logger.error("Shell executable not found: \(shell)")
            throw ScriptError.invalidShell
        }

        var outputData = Data()
        var errorData = Data()

        let outputPipe = Pipe()
        standardOutput = outputPipe

        let errorPipe = Pipe()
        standardError = errorPipe

        if !streamOutput {
            // Non-streaming execution path - simpler and more reliable for non-interactive commands
            do {
                try run()
            } catch {
                logger.error("Failed to run command: \(error.localizedDescription)")
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                throw ShellOutError(terminationStatus: terminationStatus, errorData: errorData, outputData: data)
            }

            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

            waitUntilExit()

            if terminationStatus != 0 {
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                logger.error("Command failed with status \(self.terminationStatus): \(errorMessage)")
                throw ShellOutError(
                    terminationStatus: terminationStatus,
                    errorData: errorData,
                    outputData: outputData
                )
            }
            
            let output = String(data: outputData, encoding: .utf8) ?? ""
            let err = String(data: errorData, encoding: .utf8)
            return (out: output, err: err)
        } else {
            // Streaming execution path - for interactive commands that produce output incrementally
            let outputQueue = DispatchQueue(label: "bash-output-queue")

            outputPipe.fileHandleForReading.readabilityHandler = { handler in
                let data = handler.availableData
                outputQueue.async {
                    outputData.append(data)
                    onOutputUpdate(String(data: data, encoding: .utf8))
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { handler in
                let data = handler.availableData
                outputQueue.async {
                    errorData.append(data)
                }
            }

            do {
                try run()
            } catch {
                logger.error("Failed to run streaming command: \(error.localizedDescription)")
                
                // Clean up handlers before throwing
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                
                throw ShellOutError(
                    terminationStatus: terminationStatus, 
                    errorData: errorData, 
                    outputData: outputData
                )
            }

            waitUntilExit()

            // Clean up handlers after completion
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil

            return try outputQueue.sync {
                if terminationStatus != 0 {
                    let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logger.error("Streaming command failed with status \(self.terminationStatus): \(errorMessage)")
                    
                    throw ShellOutError(
                        terminationStatus: terminationStatus,
                        errorData: errorData,
                        outputData: outputData
                    )
                }
                
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let err = String(data: errorData, encoding: .utf8)
                return (out: output, err: err)
            }
        }
    }
}

private extension FileHandle {
    var isStandard: Bool {
        self === FileHandle.standardOutput ||
            self === FileHandle.standardError ||
            self === FileHandle.standardInput
    }
}

private extension Data {
    /// Converts Data to a string, removing any trailing newline characters
    /// - Returns: UTF-8 string representation of the data with trailing newlines removed
    func shellOutput() -> String {
        guard let output = String(data: self, encoding: .utf8) else {
            return ""
        }

        // Remove trailing newline characters
        return output.trimmingCharacters(in: .newlines)
    }
}
