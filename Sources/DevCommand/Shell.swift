import Foundation

struct ShellResult {
    let stdout: String
    let stderr: String
    let exitCode: Int32
    var ok: Bool { exitCode == 0 }
    var output: String { stdout.isEmpty ? stderr : stdout }

    /// A short, single-line description of a failure, for surfacing in the UI.
    var briefError: String {
        let text = (stderr.isEmpty ? stdout : stderr).trimmingCharacters(in: .whitespacesAndNewlines)
        let line = text.split(separator: "\n").first.map(String.init) ?? text
        return line.isEmpty ? "exited with code \(exitCode)" : line
    }
}

/// Coordinates one `Shell.run`: accumulates stdout/stderr as they stream in (on the pipes'
/// reader queues), records termination, and resumes the awaiting call exactly once — only after
/// the process has exited AND both pipes hit EOF, so no output is lost. Lock-protected, hence
/// `@unchecked Sendable`, so it can be captured by the concurrent read/termination/watchdog closures.
private final class ShellRun: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<ShellResult, Never>
    private let outHandle: FileHandle
    private let errHandle: FileHandle
    private var out = Data()
    private var err = Data()
    private var outEOF = false
    private var errEOF = false
    private var terminated = false
    private var exitCode: Int32 = -1
    private var finished = false
    private var onDeliver: (() -> Void)?   // cancels the watchdog so a finished process is freed

    init(_ continuation: CheckedContinuation<ShellResult, Never>,
         outHandle: FileHandle, errHandle: FileHandle) {
        self.continuation = continuation
        self.outHandle = outHandle
        self.errHandle = errHandle
    }

    func setOnDeliver(_ block: @escaping () -> Void) { lock.lock(); onDeliver = block; lock.unlock() }

    var isFinished: Bool { lock.lock(); defer { lock.unlock() }; return finished }

    func appendOut(_ data: Data) { lock.lock(); out.append(data); lock.unlock() }
    func appendErr(_ data: Data) { lock.lock(); err.append(data); lock.unlock() }
    func markOutEOF() { lock.lock(); outEOF = true; lock.unlock(); finishIfReady() }
    func markErrEOF() { lock.lock(); errEOF = true; lock.unlock(); finishIfReady() }
    func markTerminated(_ code: Int32) {
        lock.lock(); terminated = true; exitCode = code; lock.unlock(); finishIfReady()
    }

    private func finishIfReady() {
        lock.lock()
        guard !finished, terminated, outEOF, errEOF else { lock.unlock(); return }
        finished = true
        let result = makeResult(code: exitCode)
        lock.unlock()
        deliver(result)
    }

    /// Watchdog path: finish with whatever we have (the process was killed for overrunning).
    func forceFinish() {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let result = makeResult(code: terminated ? exitCode : -1)
        lock.unlock()
        deliver(result)
    }

    func failLaunch(_ message: String) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        lock.unlock()
        deliver(ShellResult(stdout: "", stderr: message, exitCode: -1))
    }

    /// Caller must hold the lock.
    private func makeResult(code: Int32) -> ShellResult {
        ShellResult(stdout: String(decoding: out, as: UTF8.self),
                    stderr: String(decoding: err, as: UTF8.self),
                    exitCode: code)
    }

    private func deliver(_ result: ShellResult) {
        outHandle.readabilityHandler = nil
        errHandle.readabilityHandler = nil
        lock.lock(); let cancelWatchdog = onDeliver; onDeliver = nil; lock.unlock()
        cancelWatchdog?()
        continuation.resume(returning: result)
    }
}

/// Thin wrapper around `Process` for shelling out to CLI tools (lsof, xcrun, npx, kill...).
/// Output is read event-driven (no thread blocks on a pipe), and a watchdog terminates any
/// process that overruns `timeout` — so a slow or stuck subprocess can't pile up threads or
/// file descriptors across repeated polls (which previously spun the app to 100% CPU).
enum Shell {
    /// Extra paths so node/npx/xcrun/expo resolve even when launched as a bundled app —
    /// GUI apps don't inherit a login shell's PATH.
    static let extraPATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    @discardableResult
    static func run(_ executable: String,
                    _ arguments: [String] = [],
                    cwd: String? = nil,
                    extraEnv: [String: String] = [:],
                    timeout: TimeInterval = 30) async -> ShellResult {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

            var env = ProcessInfo.processInfo.environment
            env["PATH"] = env["PATH"].map { "\($0):\(extraPATH)" } ?? extraPATH
            for (key, value) in extraEnv { env[key] = value }
            process.environment = env

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe
            let outHandle = outPipe.fileHandleForReading
            let errHandle = errPipe.fileHandleForReading
            let run = ShellRun(continuation, outHandle: outHandle, errHandle: errHandle)

            outHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; run.markOutEOF() }
                else { run.appendOut(data) }
            }
            errHandle.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { handle.readabilityHandler = nil; run.markErrEOF() }
                else { run.appendErr(data) }
            }
            process.terminationHandler = { proc in run.markTerminated(proc.terminationStatus) }

            // Watchdog: terminate (then kill) a process that overruns the timeout and force the
            // call to finish. A cancellable timer source (cancelled the moment the run delivers)
            // means a finished process is freed immediately instead of pinned until the deadline.
            let watchdog = DispatchSource.makeTimerSource(queue: .global())
            watchdog.schedule(deadline: .now() + timeout)
            watchdog.setEventHandler {
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
                        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                        run.forceFinish()
                    }
                } else {
                    run.forceFinish()
                }
                watchdog.cancel()
            }
            run.setOnDeliver { watchdog.cancel() }
            watchdog.resume()

            do {
                try process.run()
            } catch {
                run.failLaunch("Failed to launch \(executable): \(error.localizedDescription)")
                return
            }
        }
    }

    /// Run a command line via zsh so login PATH and shell features are available.
    @discardableResult
    static func zsh(_ command: String, cwd: String? = nil) async -> ShellResult {
        await run("/bin/zsh", ["-lc", command], cwd: cwd)
    }
}
