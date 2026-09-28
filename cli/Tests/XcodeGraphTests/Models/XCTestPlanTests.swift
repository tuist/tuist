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

    @Test func decodes_selected_tags_and_leaves_skipped_tags_nil() throws {
        // Given: a plan whose only test target carries an include-tags filter.
        let data = Data(
            """
            {
              "configurations" : [
                {
                  "id" : "6B8C1A2E-0000-4000-8000-000000000000",
                  "name" : "Configuration 1",
                  "options" : {}
                }
              ],
              "defaultOptions" : {
                "testTimeoutsEnabled" : true
              },
              "testTargets" : [
                {
                  "selectedTags" : {
                    "tags" : [
                      ".liveNetwork"
                    ]
                  },
                  "target" : {
                    "containerPath" : "container:App.xcodeproj",
                    "identifier" : "ABC",
                    "name" : "AppTests"
                  }
                }
              ],
              "version" : 1
            }
            """.utf8
        )

        // When
        let plan = try JSONDecoder().decode(XCTestPlan.self, from: data)

        // Then
        let testTarget = try #require(plan.testTargets.first)
        #expect(testTarget.selectedTags == XCTestPlan.TagList(tags: [".liveNetwork"]))
        #expect(testTarget.skippedTags == nil)
    }

    @Test func decodes_plan_without_tag_keys_as_nil_tags() throws {
        // Given
        let data = Data(
            """
            {
              "testTargets" : [
                {
                  "target" : {
                    "containerPath" : "container:App.xcodeproj",
                    "identifier" : "ABC",
                    "name" : "AppTests"
                  }
                }
              ],
              "version" : 1
            }
            """.utf8
        )

        // When
        let plan = try JSONDecoder().decode(XCTestPlan.self, from: data)

        // Then
        let testTarget = try #require(plan.testTargets.first)
        #expect(testTarget.selectedTags == nil)
        #expect(testTarget.skippedTags == nil)
    }

    @Test func omits_tag_keys_when_encoding_a_target_without_tags() throws {
        // Given
        let testTarget = XCTestPlan.TestTarget(
            target: XCTestPlan.TestTargetReference(
                containerPath: "container:App.xcodeproj",
                identifier: "ABC",
                name: "AppTests"
            )
        )

        // When
        let json = try #require(String(data: JSONEncoder().encode(testTarget), encoding: .utf8))

        // Then
        #expect(!json.contains("selectedTags"))
        #expect(!json.contains("skippedTags"))
    }

    @Test func encodes_selected_tags_as_a_nested_tags_array() throws {
        // Given
        let testTarget = XCTestPlan.TestTarget(
            target: XCTestPlan.TestTargetReference(
                containerPath: "container:App.xcodeproj",
                identifier: "ABC",
                name: "AppTests"
            ),
            selectedTags: XCTestPlan.TagList(tags: [".contract"])
        )

        // When
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = try #require(String(data: encoder.encode(testTarget), encoding: .utf8))

        // Then
        #expect(json.contains("\"selectedTags\""))
        #expect(json.contains("\"tags\""))
        #expect(json.contains("\".contract\""))
        #expect(!json.contains("skippedTags"))
    }
}
