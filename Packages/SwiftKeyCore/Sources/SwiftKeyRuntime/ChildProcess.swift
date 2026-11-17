// Runs one program in its own process group, feeds stdin, collects stdout and stderr apart,
// and stops the whole group on a time limit or on cancel. Used by the micro-app runner and
// the login-shell PATH reader.
import Darwin
import Foundation
import SwiftKeyCore

/// Bytes that reach a program's stdin while it runs, such as the output of the step before it.
protocol ChildProcessStdinSource: AnyObject, Sendable {
    /// The bytes that came since the last call, and `true` once no more will come. Never blocks.
    func takeAvailable() -> (data: Data, finished: Bool)
}

struct ChildProcessRequest: Sendable {
    var executable: String
    /// Without the program name; `executable` becomes `argv[0]`.
    var arguments: [String]
    var environment: [String: String]
    var workingDirectory: String
    var stdin: Data = Data()
    var timeLimit: TimeInterval
    var outputLimit: Int = MicroAppRunRules.outputLimit
    /// More stdin after `stdin`, while it comes; `nil` closes stdin after `stdin`.
    var stdinSource: ChildProcessStdinSource?
    /// Each stdout chunk as it comes, also past the limit.
    var onStdout: (@Sendable (Data) -> Void)?
}

struct ChildProcessOutcome: Sendable {
    enum End: Equatable, Sendable {
        /// The exit code; 128 + the signal number when a signal ended the program.
        case exited(Int32)
        case timedOut
        case cancelled
        /// The program could not start; the value is the `errno`.
        case notStarted(Int32)
    }

    var end: End
    var stdout = Data()
    var stderr = Data()
    var stdoutCut = false
    var stderrCut = false
}

/// A cancel switch that the waiting thread checks.
final class ChildProcessCancel: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false

    func cancel() { lock.lock(); flag = true; lock.unlock() }
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return flag }
}

enum ChildProcess {
    /// After SIGTERM, the group gets SIGKILL when it is still there after this time.
    static let killGrace: TimeInterval = 1
    /// After the program ends, its pipes get this long to close.
    static let drainGrace: TimeInterval = 1
    private static let tick: Int32 = 20 // ms

    /// Runs the request on its own thread. Cancelling the task stops the program and its children.
    static func run(_ request: ChildProcessRequest) async -> ChildProcessOutcome {
        let cancel = ChildProcessCancel()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ChildProcessOutcome, Never>) in
                let thread = Thread {
                    continuation.resume(returning: runBlocking(request, cancel: cancel))
                }
                thread.name = "com.ameba.SwiftKey.child-process"
                thread.start()
            }
        } onCancel: {
            cancel.cancel()
        }
    }

    /// Blocks until the program, its children and its pipes are done.
    static func runBlocking(_ request: ChildProcessRequest, cancel: ChildProcessCancel) -> ChildProcessOutcome {
        if cancel.isCancelled { return ChildProcessOutcome(end: .cancelled) }

        var inPipe: [Int32] = [-1, -1], outPipe: [Int32] = [-1, -1], errPipe: [Int32] = [-1, -1]
        guard pipe(&inPipe) == 0 else { return ChildProcessOutcome(end: .notStarted(errno)) }
        guard pipe(&outPipe) == 0 else {
            let e = errno; closeAll(inPipe); return ChildProcessOutcome(end: .notStarted(e))
        }
        guard pipe(&errPipe) == 0 else {
            let e = errno; closeAll(inPipe + outPipe); return ChildProcessOutcome(end: .notStarted(e))
        }
        // Other programs that SwiftKey starts must not keep these pipes open.
        for fd in inPipe + outPipe + errPipe { _ = fcntl(fd, F_SETFD, FD_CLOEXEC) }

        let spawned = spawn(request, stdin: inPipe[0], stdout: outPipe[1], stderr: errPipe[1])
        close(inPipe[0]); close(outPipe[1]); close(errPipe[1])
        let pid: pid_t
        switch spawned {
        case .failure(let code):
            closeAll([inPipe[1], outPipe[0], errPipe[0]])
            return ChildProcessOutcome(end: .notStarted(code))
        case .success(let value):
            pid = value
        }

        // Writing to a closed stdin gives EPIPE instead of killing SwiftKey with SIGPIPE.
        _ = fcntl(inPipe[1], F_SETNOSIGPIPE, 1)
        for fd in [inPipe[1], outPipe[0], errPipe[0]] {
            _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        }

        var outcome = ChildProcessOutcome(end: .exited(0))
        var stdinFD: Int32 = inPipe[1], stdoutFD: Int32 = outPipe[0], stderrFD: Int32 = errPipe[0]
        var stdinOffset = 0
        var stdinBytes = [UInt8](request.stdin)
        var stdinFinished = request.stdinSource == nil
        if stdinBytes.isEmpty && stdinFinished { close(stdinFD); stdinFD = -1 }

        let deadline = Date().addingTimeInterval(request.timeLimit)
        var stopReason: ChildProcessOutcome.End?
        var killAt: Date?
        var exitCode: Int32?
        var drainUntil: Date?
        var buffer = [UInt8](repeating: 0, count: 65_536)

        func readAvailable(_ fd: inout Int32, into data: inout Data, cut: inout Bool, onChunk: (@Sendable (Data) -> Void)? = nil) {
            while fd >= 0 {
                let n = read(fd, &buffer, buffer.count)
                if n > 0 {
                    let chunk = Data(buffer[0..<n])
                    onChunk?(chunk)
                    // Past the limit the bytes are read and dropped, so the program is never blocked.
                    if MicroAppRunRules.append(chunk, to: &data, limit: request.outputLimit) { cut = true }
                } else if n == 0 || (errno != EAGAIN && errno != EINTR) {
                    close(fd); fd = -1
                } else {
                    return
                }
            }
        }

        while true {
            // Has the program ended?
            if exitCode == nil {
                var status: Int32 = 0
                let r = waitpid(pid, &status, WNOHANG)
                if r == pid || (r == -1 && errno == ECHILD) {
                    exitCode = r == pid ? decode(status) : -1
                    // Children left behind are stopped too: the run is one command.
                    _ = killpg(pid, SIGKILL)
                    drainUntil = Date().addingTimeInterval(drainGrace)
                }
            }
            if exitCode != nil, stdoutFD < 0, stderrFD < 0 { break }
            if let drainUntil, Date() >= drainUntil { break }

            // Time limit and cancel.
            if exitCode == nil {
                let now = Date()
                if stopReason == nil {
                    if cancel.isCancelled {
                        stopReason = .cancelled
                    } else if now >= deadline {
                        stopReason = .timedOut
                    }
                    if stopReason != nil {
                        _ = killpg(pid, SIGTERM)
                        killAt = now.addingTimeInterval(killGrace)
                    }
                } else if let at = killAt, now >= at {
                    _ = killpg(pid, SIGKILL)
                    killAt = nil
                }
            }

            // More stdin from the source, while the program reads it.
            if !stdinFinished, let source = request.stdinSource {
                let (more, finished) = source.takeAvailable()
                if stdinFD >= 0 {
                    if stdinOffset > 0 && stdinOffset == stdinBytes.count { stdinBytes = []; stdinOffset = 0 }
                    stdinBytes.append(contentsOf: more)
                }
                stdinFinished = finished
            }

            var fds: [pollfd] = []
            if stdoutFD >= 0 { fds.append(pollfd(fd: stdoutFD, events: Int16(POLLIN), revents: 0)) }
            if stderrFD >= 0 { fds.append(pollfd(fd: stderrFD, events: Int16(POLLIN), revents: 0)) }
            if stdinFD >= 0 && stdinOffset < stdinBytes.count { fds.append(pollfd(fd: stdinFD, events: Int16(POLLOUT), revents: 0)) }
            _ = poll(&fds, nfds_t(fds.count), tick)

            readAvailable(&stdoutFD, into: &outcome.stdout, cut: &outcome.stdoutCut, onChunk: request.onStdout)
            readAvailable(&stderrFD, into: &outcome.stderr, cut: &outcome.stderrCut)

            if stdinFD >= 0 {
                if exitCode != nil {
                    close(stdinFD); stdinFD = -1
                } else {
                    var failed = false
                    if stdinOffset < stdinBytes.count {
                        let n = stdinBytes.withUnsafeBufferPointer { p in
                            write(stdinFD, p.baseAddress! + stdinOffset, p.count - stdinOffset)
                        }
                        if n > 0 { stdinOffset += n }
                        failed = n < 0 && errno != EAGAIN && errno != EINTR
                    }
                    if failed || (stdinOffset >= stdinBytes.count && stdinFinished) {
                        close(stdinFD); stdinFD = -1
                    }
                }
            }
        }

        closeAll([stdinFD, stdoutFD, stderrFD])
        if let stopReason {
            outcome.end = stopReason
        } else {
            outcome.end = .exited(exitCode ?? -1)
        }
        return outcome
    }

    /// The exit code of a `waitpid` status; 128 + the signal number for a signal.
    static func decode(_ status: Int32) -> Int32 {
        let signal = status & 0x7F
        return signal == 0 ? (status >> 8) & 0xFF : 128 + signal
    }

    private static func closeAll(_ fds: [Int32]) {
        for fd in fds where fd >= 0 { close(fd) }
    }

    private enum SpawnResult {
        case success(pid_t)
        case failure(Int32)
    }

    private static func spawn(_ request: ChildProcessRequest, stdin: Int32, stdout: Int32, stderr: Int32) -> SpawnResult {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_adddup2(&actions, stdin, 0)
        posix_spawn_file_actions_adddup2(&actions, stdout, 1)
        posix_spawn_file_actions_adddup2(&actions, stderr, 2)
        posix_spawn_file_actions_addchdir_np(&actions, request.workingDirectory)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Own process group, so the program and its children can be stopped together;
        // no other open files; default signal handling and an empty signal mask.
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var all = sigset_t(), none = sigset_t()
        sigfillset(&all)
        sigemptyset(&none)
        posix_spawnattr_setsigdefault(&attributes, &all)
        posix_spawnattr_setsigmask(&attributes, &none)

        let argv = ([request.executable] + request.arguments).map { strdup($0) } + [nil]
        let envp = request.environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            for p in argv { free(p) }
            for p in envp { free(p) }
        }
        var pid: pid_t = 0
        let result = posix_spawn(&pid, request.executable, &actions, &attributes, argv, envp)
        return result == 0 ? .success(pid) : .failure(result)
    }
}
