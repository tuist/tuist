import Foundation

private struct Reconnect: Error {}

extension AppClient {
    /// Keeps the live socket of thread `id`, or of the whole inbox with `inbox`,
    /// open while the calling task runs.
    /// The core decides everything about it (`live_wait`, `live_connect`,
    /// `live_tick`, `live_receive`, `live_close`): how long to wait before opening it, when
    /// to heartbeat, when a silent socket must be reopened, and what each
    /// frame means. The server's changes call `refresh`, and the agent's calls
    /// to the tools Luft offers, such as `set_theme`, are applied here before
    /// the core's answer goes back. A thread's socket instead keeps the core's
    /// store in sync with the server's diffs, and calls `changed` after each
    /// one it stored, to read the thread from the store again.
    func live(
        _ id: String,
        changed: (@MainActor () async -> Void)? = nil,
        refresh: @escaping @MainActor () async -> Void
    ) async {
        let socket = UUID().uuidString
        while !Task.isCancelled {
            do {
                try await liveOnce(id, socket: socket, changed: changed, refresh: refresh)
            } catch {
                // Offline, refused, silent or closed: connect again after the
                // core's delay. The conversation still polls meanwhile.
            }
        }
        _ = try? await call("live_close", ["socket": socket])
    }

    private func liveOnce(
        _ id: String,
        socket: String,
        changed: (@MainActor () async -> Void)?,
        refresh: @escaping @MainActor () async -> Void
    ) async throws {
        // Every attempt waits as the core says first, so failures back off
        // whether connecting, joining or a live socket failed.
        let wait = try await call("live_wait", ["socket": socket])
        try await Task.sleep(for: .milliseconds(wait["delay_ms"] as? Int ?? 0))
        let plan = try await call("live_connect", ["id": id, "socket": socket])
        guard let url = URL(string: plan["url"] as? String ?? ""),
              let protocols = plan["protocols"] as? [String],
              let join = plan["join"] as? String
        else { throw Reconnect() }
        let interval = plan["tick_ms"] as? Int ?? 30000
        // Refreshes run beside the socket, at most one per `refresh_ms` as the core says:
        // requests made meanwhile fold into one that follows, and frames and heartbeats
        // keep flowing while a refresh loads.
        let spacing = plan["refresh_ms"] as? Int ?? 0
        let (requests, request) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        let refresher = Task {
            for await _ in requests {
                await refresh()
                if spacing > 0 { try? await Task.sleep(for: .milliseconds(spacing)) }
            }
        }
        let task = URLSession.shared.webSocketTask(with: url, protocols: protocols)
        task.resume()
        // Closing the task ends `receive()` with an error, which reconnects.
        let ticks = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(interval))
                guard !Task.isCancelled, let tick = try? await call("live_tick", ["socket": socket]) else { return }
                do {
                    for frame in tick["send"] as? [String] ?? [] {
                        try await task.send(.string(frame))
                    }
                } catch {
                    task.cancel(with: .goingAway, reason: nil)
                    return
                }
                if tick["reconnect"] as? Bool == true {
                    task.cancel(with: .goingAway, reason: nil)
                    return
                }
            }
        }
        defer {
            ticks.cancel()
            request.finish()
            refresher.cancel()
            task.cancel(with: .goingAway, reason: nil)
        }
        try await withTaskCancellationHandler {
            try await task.send(.string(join))
            while true {
                guard case let .string(text) = try await task.receive() else { continue }
                let frame = try await call("live_receive", ["id": id, "socket": socket, "message": text])
                // Applied before answering, so the agent hears it took effect.
                if let theme = frame["theme"] as? [String: Any] { Themes.shared.apply(custom: theme) }
                for reply in frame["replies"] as? [String] ?? [] {
                    try await task.send(.string(reply))
                }
                if frame["refresh"] as? Bool == true { request.yield() }
                // A local read, so it runs at once rather than spaced like a load.
                if frame["changed"] as? Bool == true { await changed?() }
                if frame["reconnect"] as? Bool == true { throw Reconnect() }
            }
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }
}
