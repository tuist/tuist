import Foundation
import Testing

@testable import TuistServer

struct CommandArgumentsCompatibilityTests {
    @Test(arguments: [0, 1, 2, 3])
    func responses_accept_missing_unknown_empty_and_recorded_arguments(state: Int) throws {
        let arguments = ["generate", "--configuration", "Debug Scheme", "FocusedTargetName", "", "a\"b", "🎯"]
        let legacyArguments = state == 2 ? "" : arguments.joined(separator: " ")
        var payload: [String: Any] = [
            "id": "generation-id", "duration": 1, "status": "success", "is_ci": false,
            "ran_at": 1_790_812_800, "url": "https://tuist.example/generation",
            "command_arguments": legacyArguments,
        ]
        switch state {
        case 1: payload["command_arguments_array"] = NSNull()
        case 2: payload["command_arguments_array"] = [String]()
        case 3: payload["command_arguments_array"] = arguments
        default: break
        }
        let expected: [String]? = state == 3 ? arguments : (state == 2 ? [] : nil)
        let decoder = JSONDecoder()
        let data = try JSONSerialization.data(withJSONObject: payload)
        let generation = try decoder.decode(Operations.getGeneration.Output.Ok.Body.jsonPayload.self, from: data)
        let listed = try decoder.decode(
            Operations.listGenerations.Output.Ok.Body.jsonPayload.generationsPayloadPayload.self,
            from: data
        )
        #expect(generation.command_arguments_array == expected)
        #expect(listed.command_arguments_array == expected)
        #expect(generation.command_arguments == legacyArguments)
        #expect(listed.command_arguments == legacyArguments)
        #expect(try decoder.decode(OlderCommandArgumentsResponse.self, from: data).command_arguments == legacyArguments)

        payload.merge([
            "id": 42, "name": "generate", "subcommand": "", "tuist_version": "4.0",
            "swift_version": "6.0", "macos_version": "15.0", "git_commit_sha": "", "git_ref": "", "git_branch": "main",
        ]) { _, new in new }
        let runData = try JSONSerialization.data(withJSONObject: payload)
        let run = try decoder.decode(Components.Schemas.Run.self, from: runData)
        #expect(run.command_arguments_array == expected)
        #expect(run.command_arguments == legacyArguments)

        payload["command_arguments"] = NSNull()
        let historicalRun = try decoder.decode(
            Components.Schemas.Run.self,
            from: JSONSerialization.data(withJSONObject: payload)
        )
        #expect(historicalRun.command_arguments == nil)
    }
}

private struct OlderCommandArgumentsResponse: Decodable {
    let command_arguments: String?
}
