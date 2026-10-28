import Foundation
import Testing

@testable import TuistServer

struct ReportActorCompatibilityTests {
    @Test(arguments: [0, 1, 2])
    func report_responses_accept_absent_null_and_future_actor_metadata(state: Int) throws {
        var payload: [String: Any] = [
            "type": "build", "id": "report-id", "duration": 1, "project_id": 1,
            "url": "https://tuist.example/report", "name": "generate", "future_field": ["ignored": true],
        ]
        if state == 1 {
            payload["actor"] = NSNull()
        } else if state == 2 {
            payload["actor"] = [
                "name": "opaque", "source": "future-source", "submission_auth": "future-auth",
                "claimed_actor_id": "opaque", "verified_account_handle": NSNull(), "future_field": ["ignored": true],
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(withJSONObject: payload)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let build = try decoder.decode(Components.Schemas.RunsBuild.self, from: data)
        let event = try decoder.decode(Components.Schemas.CommandEvent.self, from: data)
        let gradle = try decoder.decode(Operations.createGradleBuild.Output.Created.Body.jsonPayload.self, from: data)
        let mix = try decoder.decode(Operations.createMixBuild.Output.Created.Body.jsonPayload.self, from: data)
        #expect(build.id == "report-id")
        #expect(event.id == "report-id")
        #expect(gradle.id == "report-id")
        #expect(mix.id == "report-id")
        for actor in [build.actor, event.actor, gradle.actor, mix.actor] {
            #expect(actor?.source == (state == 2 ? "future-source" : nil))
            #expect(actor?.submission_auth == (state == 2 ? "future-auth" : nil))
        }
        #expect(try decoder.decode(OlderBuildResponse.self, from: data).id == "report-id")

        payload["type"] = "test"
        payload["test_case_runs"] = [[
            "id": "case-id", "name": "test", "module_name": "Module", "suite_name": "Suite",
            "actor": payload["actor"] ?? NSNull(), "future_field": true,
        ]]
        let test = try decoder.decode(
            Components.Schemas.RunsTest.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
        #expect(test.actor?.source == (state == 2 ? "future-source" : nil))
        #expect(test.test_case_runs.first?.actor?.source == test.actor?.source)

        payload.merge([
            "id": 42, "subcommand": "", "command_arguments": [String](), "tuist_version": "4.0",
            "swift_version": "6.0", "macos_version": "15.0", "status": "success", "is_ci": false,
            "git_commit_sha": "", "git_ref": "", "git_branch": "main", "ran_at": 1_790_812_800,
        ]) { _, new in new }
        let run = try decoder.decode(Components.Schemas.Run.self, from: JSONSerialization.data(withJSONObject: payload))
        #expect(run.actor?.source == (state == 2 ? "future-source" : nil))
    }
}

private struct OlderBuildResponse: Decodable {
    let id: String
    let url: String
}
