import Foundation
import Testing

@testable import TuistLoader

struct XCTestPlanTests {
    @Test func decodes_bare_container_path_as_empty_project_path() throws {
        // Given
        let data = Data(
            """
            {
              "testTargets" : [
                {
                  "target" : {
                    "containerPath" : "container:",
                    "identifier" : "AppTests",
                    "name" : "AppTests"
                  }
                }
              ]
            }
            """.utf8
        )

        // When
        let got = try JSONDecoder().decode(XCTestPlan.self, from: data)

        // Then
        #expect(got.testTargets.count == 1)
        #expect(got.testTargets.first?.target.projectPath == "")
        #expect(got.testTargets.first?.target.name == "AppTests")
    }

    @Test func decodes_container_path_with_project_reference() throws {
        // Given
        let data = Data(
            """
            {
              "testTargets" : [
                {
                  "target" : {
                    "containerPath" : "container:App.xcodeproj",
                    "identifier" : "AppTests",
                    "name" : "AppTests"
                  }
                }
              ]
            }
            """.utf8
        )

        // When
        let got = try JSONDecoder().decode(XCTestPlan.self, from: data)

        // Then
        #expect(got.testTargets.first?.target.projectPath == "App.xcodeproj")
    }

    @Test func decodes_container_path_with_colon_in_path() throws {
        // Given
        let data = Data(
            """
            {
              "testTargets" : [
                {
                  "target" : {
                    "containerPath" : "container:path/with:colon.xcodeproj",
                    "identifier" : "AppTests",
                    "name" : "AppTests"
                  }
                }
              ]
            }
            """.utf8
        )

        // When
        let got = try JSONDecoder().decode(XCTestPlan.self, from: data)

        // Then
        #expect(got.testTargets.first?.target.projectPath == "path/with:colon.xcodeproj")
    }
}
