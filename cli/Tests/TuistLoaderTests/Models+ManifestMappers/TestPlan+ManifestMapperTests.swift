import FileSystem
import Foundation
import ProjectDescription
import Testing
import XcodeGraph

@testable import TuistLoader

struct TestPlanManifestMapperTests {
    private let fileSystem = FileSystem()

    @Test func plan_when_manifest_directory_is_in_a_subdirectory() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: UUID().uuidString) { temporaryDirectory in
            // Given
            let testPlanPath = temporaryDirectory.appending(component: "TestPlan.xctestplan")
            let manifestDirectory = temporaryDirectory.appending(component: "App")
            try await fileSystem.writeText(
                """
                {
                  "testTargets" : [
                    {
                      "target" : {
                        "containerPath" : "container:App.xcodeproj",
                        "identifier" : "99DCC7BD0ABB09C467644299",
                        "name" : "AppTests"
                      }
                    }
                  ]
                }
                """,
                at: testPlanPath
            )

            // When
            let got = try await TestPlan.from(
                path: testPlanPath,
                isDefault: false,
                generatorPaths: GeneratorPaths(
                    manifestDirectory: manifestDirectory,
                    rootDirectory: temporaryDirectory
                )
            )

            // Then
            #expect(
                got == TestPlan(
                    path: testPlanPath,
                    testTargets: [
                        TestableTarget(
                            target: TargetReference(
                                projectPath: manifestDirectory,
                                name: "AppTests"
                            )
                        ),
                    ],
                    isDefault: false
                )
            )
        }
    }
}
