import Dispatch
import Foundation

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

public enum ThreadDumpSignalHandler {
    private static let outputLock = NSLock()
    private static var source: DispatchSourceSignal?

    public static func installIfEnabled() {
        guard Environment.current.isVariableTruthy("TUIST_THREAD_DUMP_SIGNAL") else { return }
        outputLock.lock()
        defer { outputLock.unlock() }
        guard source == nil else { return }

        signal(SIGUSR1, SIG_IGN)

        let queue = DispatchQueue(label: "dev.tuist.thread-dump-signal")
        let signalSource = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: queue)
        signalSource.setEventHandler {
            if Environment.current.isVariableTruthy("TUIST_THREAD_DUMP_SAMPLE") {
                dumpSample()
            } else {
                dumpCurrentThreadStack()
            }
        }
        signalSource.resume()
        source = signalSource
    }

    private static func dumpCurrentThreadStack() {
        let thread = Thread.current
        let header = "\n[TUIST] SIGUSR1 received. Thread dump (current thread only): \nThread: \(thread)\n"
        let stack = Thread.callStackSymbols.joined(separator: "\n")
        outputToStandardError(header + stack + "\n")
    }

    private static func dumpSample() {
        #if os(macOS)
            let pid = ProcessInfo.processInfo.processIdentifier
            let header = "\n[TUIST] SIGUSR1 received. Capturing sample for pid \(pid)...\n"
            outputToStandardError(header)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
            process.arguments = ["\(pid)", "1", "-mayDie"]
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let text = String(data: data, encoding: .utf8), !text.isEmpty {
                    outputToStandardError(text + "\n")
                } else {
                    outputToStandardError("[TUIST] sample produced no output.\n")
                }
            } catch {
                outputToStandardError("[TUIST] Failed to run /usr/bin/sample: \(error)\n")
            }
        #else
            outputToStandardError("[TUIST] sample is only supported on macOS. Falling back to current thread.\n")
            dumpCurrentThreadStack()
        #endif
    }

    private static func outputToStandardError(_ message: String) {
        outputLock.lock()
        defer { outputLock.unlock() }
        guard let data = message.data(using: .utf8) else { return }
        FileHandle.standardError.write(data)
    }
}
