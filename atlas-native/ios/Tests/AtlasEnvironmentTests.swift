import Foundation
import Testing

@MainActor
struct AtlasEnvironmentTests {
    @Test func queuedJobsNeedNoDecisionAndCancellationIsBoundToTheJobAndDeparture() async throws {
        var stopping = false
        var posted: [String: Any]?
        let model = AtlasEnvironmentActivity(threadId: "thread") { action in
            if action["action"] as? String == "cancel_command" { posted = action; stopping = true }
            return try self.activity(status: "queued", stopping: stopping)
        }
        let watcher = Task { await model.watch() }
        defer { watcher.cancel(); model.stop() }
        while model.commands.isEmpty { await Task.yield() }
        let job = try #require(model.commands.first)
        #expect(job.phase == "Waiting for Mac")
        #expect(posted == nil)
        await model.cancel(job)
        #expect(posted?["digest"] as? String == job.digest)
        #expect(posted?["thread_id"] as? String == "thread")
        #expect(posted?["command_id"] as? String == job.id)
        #expect(posted?["approved"] == nil)
        #expect(model.commands.first?.phase == "Stopping · waiting for Mac")
        model.stop()
        posted = nil
        await model.cancel(job)
        #expect(posted == nil)
    }

    @Test func cancellationWaitsForDeviceAndUnknownOutcomesStayExplicit() async throws {
        var stopping = false
        let model = AtlasEnvironmentActivity(threadId: "thread") { action in
            if action["action"] as? String == "cancel_command" { stopping = true }
            return try self.activity(status: "claimed", stopping: stopping)
        }
        let watcher = Task { await model.watch() }
        defer { watcher.cancel(); model.stop() }
        while model.commands.isEmpty { await Task.yield() }
        await model.cancel(try #require(model.commands.first))
        #expect(model.commands.first?.status == "claimed")
        #expect(model.commands.first?.phase == "Stopping · waiting for Mac")
        struct Activity: Decodable { let commands: [AtlasEnvironmentJob] }
        let unknown = try AtlasEnvironmentCoding.decode(Activity.self, from: activity(status: "unknown"))
        #expect(unknown.commands.first?.active == false)
        #expect(unknown.commands.first?.phase == "Outcome unknown · not retried")
    }

    @Test func departedReadsAndRevokedAccessCannotRestoreProtectedCommands() async throws {
        var resume: CheckedContinuation<Data, Never>?
        let model = AtlasEnvironmentActivity(threadId: "thread") { _ in
            await withCheckedContinuation { resume = $0 }
        }
        let pending = Task { await model.refresh() }
        while resume == nil { await Task.yield() }
        model.stop()
        resume?.resume(returning: try activity(status: "claimed"))
        _ = await pending.value
        #expect(model.commands.isEmpty)

        var revoked = false
        let protected = AtlasEnvironmentActivity(threadId: "thread") { _ in
            if revoked { throw AtlasAuthenticationError(kind: "forbidden", message: "Unavailable") }
            return try self.activity(status: "claimed")
        }
        #expect(await protected.refresh())
        #expect(protected.commands.count == 1)
        revoked = true
        #expect(!(await protected.refresh()))
        #expect(protected.commands.isEmpty)
    }

    private func activity(status: String, stopping: Bool = false) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["commands": [[
            "id": "01922cc0-0000-7000-8000-000000000001", "message_id": "01922cc0-0000-7000-8000-000000000002",
            "environment_id": "01922cc0-0000-7000-8000-000000000003", "environment_name": "Build Mac",
            "project_id": "01922cc0-0000-7000-8000-000000000004", "project_name": "Application",
            "digest": String(repeating: "b", count: 64), "command": "xcodebuild -scheme Example build", "status": status,
            "output": "", "success": NSNull(), "cancel_requested": stopping, "progress_sequence": 7,
            "execution_timeout_seconds": 1800
        ]]])
    }
}
