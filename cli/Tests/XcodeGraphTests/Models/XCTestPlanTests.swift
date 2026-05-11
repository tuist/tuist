import Foundation
import Testing
import XcodeGraph

struct XCTestPlanTests {
    @Test func decodes_real_world_xctestplan_with_mixed_option_values() throws {
        // Given: a real `.xctestplan` payload with booleans and a nested target reference
        // in `defaultOptions` — the shape Xcode actually produces.
        let data = Data(
            """
            {
              "configurations" : [
                {
                  "id" : "07C2DFDA-784B-485A-AFF0-A8CDBE98F8FA",
                  "name" : "Configuration 1",
                  "options" : {}
                }
              ],
              "defaultOptions" : {
                "codeCoverage" : false,
                "targetForVariableExpansion" : {
                  "containerPath" : "container:App.xcodeproj",
                  "identifier" : "93E9E330FC2CE7458D9C925F",
                  "name" : "App"
                }
              },
              "testTargets" : [
                {
                  "target" : {
                    "containerPath" : "container:App.xcodeproj",
                    "identifier" : "99DCC7BD0ABB09C467644299",
                    "name" : "AppTests"
                  }
                }
              ],
              "version" : 1
            }
            """.utf8
        )

        // When / Then: decoding succeeds and round-trips the mixed-type payload.
        let plan = try JSONDecoder().decode(XCTestPlan.self, from: data)
        #expect(plan.version == 1)
        #expect(plan.testTargets.first?.target.name == "AppTests")
        #expect(plan.defaultOptions?["codeCoverage"]?.value as? Bool == false)
        let variableExpansion = try #require(
            plan.defaultOptions?["targetForVariableExpansion"]?.value as? [String: Any]
        )
        #expect(variableExpansion["name"] as? String == "App")
    }
}
