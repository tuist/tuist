import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if os(Linux)
    import Glibc
#else
    import Darwin
#endif

enum RunnerShellTerminalClientError: LocalizedError, Equatable {
    case notInteractive

    var errorDescription: String? {
        switch self {
        case .notInteractive:
            return "Runner shell access requires an interactive terminal."
        }
    }
}

protocol RunnerShellTerminalClienting {
    func attach(to session: RunnerShellSession) async throws
}

struct RunnerShellTerminalClient: RunnerShellTerminalClienting {
    private let urlSession: URLSession

    init(urlSession: URLSession = .tuistShared) {
        self.urlSession = urlSession
    }

    func attach(to session: RunnerShellSession) async throws {
        let terminalMode = try TerminalRawMode()
        let webSocketTask = urlSession.webSocketTask(
            with: session.websocketURL,
            protocols: [session.websocketProtocol]
        )
        let inputForwarder = StandardInputForwarder(webSocketTask: webSocketTask)
        let resizeObserver = TerminalResizeObserver {
            Task {
                try? await Self.sendResize(to: webSocketTask)
            }
        }

        defer {
            inputForwarder.stop()
            resizeObserver.cancel()
            webSocketTask.cancel(with: .goingAway, reason: nil)
            terminalMode.restore()
        }

        webSocketTask.resume()
        inputForwarder.start()
        try await Self.sendResize(to: webSocketTask)
        try await receiveOutput(from: webSocketTask)
    }

    private func receiveOutput(from webSocketTask: URLSessionWebSocketTask) async throws {
        do {
            while true {
                switch try await webSocketTask.receive() {
                case let .data(data):
                    FileHandle.standardOutput.write(data)
                case .string:
                    continue
                @unknown default:
                    continue
                }
            }
        } catch {
            if (error as? URLError)?.code == .cancelled {
                return
            }

            throw error
        }
    }

    private static func sendResize(to webSocketTask: URLSessionWebSocketTask) async throws {
        let size = TerminalSize.current()
        let payload = try JSONEncoder().encode(size)
        guard let text = String(data: payload, encoding: .utf8) else { return }

        try await webSocketTask.send(.string(text))
    }
}

private struct TerminalSize: Encodable {
    let type = "resize"
    let columns: Int
    let rows: Int

    static func current() -> TerminalSize {
        var size = winsize()

        #if os(Linux)
            let request = UInt(TIOCGWINSZ)
        #else
            let request = TIOCGWINSZ
        #endif

        if ioctl(STDOUT_FILENO, request, &size) == 0, size.ws_col > 0, size.ws_row > 0 {
            return TerminalSize(columns: Int(size.ws_col), rows: Int(size.ws_row))
        }

        return TerminalSize(columns: 80, rows: 24)
    }
}

private final class TerminalRawMode {
    private var original = termios()
    private var restored = false

    init() throws {
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw RunnerShellTerminalClientError.notInteractive
        }

        guard tcgetattr(STDIN_FILENO, &original) == 0 else {
            throw RunnerShellTerminalClientError.notInteractive
        }

        var raw = original
        cfmakeraw(&raw)
        guard tcsetattr(STDIN_FILENO, TCSANOW, &raw) == 0 else {
            throw RunnerShellTerminalClientError.notInteractive
        }
    }

    deinit {
        restore()
    }

    func restore() {
        guard !restored else { return }
        tcsetattr(STDIN_FILENO, TCSANOW, &original)
        restored = true
    }
}

private final class StandardInputForwarder {
    private let webSocketTask: URLSessionWebSocketTask

    init(webSocketTask: URLSessionWebSocketTask) {
        self.webSocketTask = webSocketTask
    }

    func start() {
        FileHandle.standardInput.readabilityHandler = { [webSocketTask] handle in
            let data = handle.availableData

            if data.isEmpty {
                webSocketTask.cancel(with: .goingAway, reason: nil)
                return
            }

            Task {
                try? await webSocketTask.send(.data(data))
            }
        }
    }

    func stop() {
        FileHandle.standardInput.readabilityHandler = nil
    }
}

private final class TerminalResizeObserver {
    private let source: DispatchSourceSignal

    init(onResize: @escaping @Sendable () -> Void) {
        signal(SIGWINCH, SIG_IGN)

        source = DispatchSource.makeSignalSource(signal: SIGWINCH, queue: DispatchQueue.global())
        source.setEventHandler(handler: onResize)
        source.resume()
    }

    func cancel() {
        source.cancel()
    }
}
