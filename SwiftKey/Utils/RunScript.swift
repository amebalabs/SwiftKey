import Dispatch
import Foundation
import os

private let logger = os.Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.swiftkey", category: "RunScript")
let sharedEnv = ProcessEnv.shared

enum ScriptError: Error {
    case emptyCommand
    case executionFailed(Int32, String)
    case invalidShell

    var localizedDescription: String {
        switch self {
        case .emptyCommand:
            return "Empty command provided"
        case let .executionFailed(status, message):
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

/// Runs a shell command and returns the output asynchronously
/// - Parameters:
///   - command: The shell command to run
///   - args: Optional arguments for the command
///   - process: Optional custom Process object
///   - env: Optional environment variables to set
///   - runInBash: Whether to run in bash shell
/// - Returns: A tuple with stdout and stderr output
@discardableResult @available(macOS 10.15, *)
func runScript(
    to command: String,
    args: [String] = [],
    process: Process = Process(),
    env: [String: String] = [:],
    runInBash: Bool = true
) async throws -> (out: String, err: String?) {
    // Pre-execution validation
    let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)

    // Ensure command is not empty
    guard !trimmedCommand.isEmpty else {
        logger.error("Empty command provided")
        throw ScriptError.emptyCommand
    }

    // Set up execution environment
    let swiftbarEnv = sharedEnv.systemEnvStr.merging(env) { current, _ in current }
    process.environment = swiftbarEnv.merging(ProcessInfo.processInfo.environment) { current, _ in current }

    // Execute command with enhanced error handling
    return try await process.launchScript(
        with: trimmedCommand,
        args: args,
        runInBash: runInBash
    )
}

/// Legacy version of runScript for backward compatibility
/// - Note: This function is deprecated and will be removed in a future version
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

// MARK: - Command line

/// How a command from the config reaches the shell: as its text, so the command that runs is the
/// one that was approved.
enum ShellCommandLine {
    /// The arguments of `zsh` for `script`. The text is the shell code as it is, except that one pair
    /// of single quotes around the whole command (`'cd ~/x && git status'`, the form the README
    /// shows) is removed. `args` are passed as positional parameters, so they never change how the
    /// command is split.
    static func arguments(for script: String, args: [String]) -> [String] {
        let code = command(from: script)
        if args.isEmpty { return ["-l", "-c", code] }
        return ["-l", "-c", code + " \"$@\"", "zsh"] + args
    }

    /// The shell code of a command from the config.
    static func command(from script: String) -> String {
        let text = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") else { return text }
        let inner = text.dropFirst().dropLast()
        // A quote inside means the outer pair does not wrap the whole command, as in `'a' 'b'`.
        guard !inner.contains("'") else { return text }
        return String(inner)
    }
}

// MARK: - Private

private extension Process {
    /// Asynchronous version of launchScript using async/await
    @discardableResult
    func launchScript(
        with script: String,
        args: [String],
        runInBash: Bool = true
    ) async throws -> (out: String, err: String?) {
        let shell = "/bin/zsh"
        executableURL = URL(fileURLWithPath: shell)
        arguments = ShellCommandLine.arguments(for: script, args: args)

        guard let executableURL = executableURL, FileManager.default.fileExists(atPath: executableURL.path) else {
            logger.error("Shell executable not found: \(shell)")
            throw ScriptError.invalidShell
        }

        let outputPipe = Pipe()
        standardOutput = outputPipe

        let errorPipe = Pipe()
        standardError = errorPipe

        // Both pipes are drained while the command runs, so a command with a lot of output never
        // blocks on a full pipe; the termination handler then resumes exactly once.
        return try await withCheckedThrowingContinuation { continuation in
            let drained = DispatchGroup()
            let output = PipeDrain(), errors = PipeDrain()
            for (pipe, drain) in [(outputPipe, output), (errorPipe, errors)] {
                drained.enter()
                DispatchQueue.global(qos: .userInitiated).async {
                    drain.data = pipe.fileHandleForReading.readDataToEndOfFile()
                    drained.leave()
                }
            }

            terminationHandler = { process in
                drained.notify(queue: .global(qos: .userInitiated)) {
                    let outputData = output.data
                    let errorData = errors.data
                    if process.terminationStatus != 0 {
                        let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        logger.error("Command failed with status \(process.terminationStatus): \(errorMessage)")
                        continuation.resume(throwing: ShellOutError(
                            terminationStatus: process.terminationStatus,
                            errorData: errorData,
                            outputData: outputData
                        ))
                    } else {
                        let out = String(data: outputData, encoding: .utf8) ?? ""
                        let err = String(data: errorData, encoding: .utf8)
                        continuation.resume(returning: (out: out, err: err))
                    }
                }
            }

            do {
                try run()
            } catch {
                // The command never started: no termination handler will run. Close the pipes so
                // the drains end.
                terminationHandler = nil
                try? outputPipe.fileHandleForWriting.close()
                try? errorPipe.fileHandleForWriting.close()
                logger.error("Failed to run command: \(error.localizedDescription)")
                continuation.resume(throwing: error)
            }
        }
    }

    @discardableResult func launchScript(
        with script: String,
        args: [String],
        runInBash: Bool = true,
        streamOutput: Bool,
        onOutputUpdate: @escaping (String?) -> Void
    ) throws -> (out: String, err: String?) {
        let shell = "/bin/zsh"
        executableURL = URL(fileURLWithPath: shell)
        arguments = ShellCommandLine.arguments(for: script, args: args)

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

/// The bytes one pipe gave, written by its reading thread and read after it finished.
private final class PipeDrain: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    var data: Data {
        get { lock.withLock { bytes } }
        set { lock.withLock { bytes = newValue } }
    }
}
