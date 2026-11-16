// Runs an AppleScript with /usr/bin/osascript, for the Finder and browser context of a micro-app.
import Foundation
import SwiftKeyCore

/// The end of one osascript run.
package struct MicroAppScriptResult: Equatable, Sendable {
    package enum End: Equatable, Sendable {
        case success
        /// osascript failed; its error text says why (such as `(-1743)`).
        case failure
        /// The time limit passed and osascript was stopped.
        case timedOut
        case cancelled
    }

    package var end: End
    package var stdout: String
    package var stderr: String

    package init(end: End, stdout: String = "", stderr: String = "") {
        self.end = end
        self.stdout = stdout
        self.stderr = stderr
    }
}

package enum MicroAppScript {
    /// Runs `script` and waits at most `timeLimit` seconds. The Automation prompt of macOS, shown at
    /// the first run for an app, counts against the limit.
    package static func run(_ script: String, timeLimit: TimeInterval = 60) async -> MicroAppScriptResult {
        let request = ChildProcessRequest(executable: "/usr/bin/osascript", arguments: ["-e", script], environment: [:],
                                          workingDirectory: "/", timeLimit: timeLimit, outputLimit: MicroAppRunRules.outputLimit)
        let outcome = await ChildProcess.run(request)
        let stdout = String(decoding: outcome.stdout, as: UTF8.self)
        let stderr = String(decoding: outcome.stderr, as: UTF8.self)
        switch outcome.end {
        case .exited(0): return MicroAppScriptResult(end: .success, stdout: stdout, stderr: stderr)
        case .timedOut: return MicroAppScriptResult(end: .timedOut, stdout: stdout, stderr: stderr)
        case .cancelled: return MicroAppScriptResult(end: .cancelled, stdout: stdout, stderr: stderr)
        default: return MicroAppScriptResult(end: .failure, stdout: stdout, stderr: stderr)
        }
    }
}
