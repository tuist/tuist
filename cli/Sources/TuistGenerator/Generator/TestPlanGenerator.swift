import Foundation
import Path
import TuistCore
import XcodeGraph
import XcodeProj

/// Builds `TestPlanDescriptor` values from the graph's generated test plans and the generated projects that own their targets.
enum TestPlanGenerator {
    /// Produces a descriptor for a generated test plan, returning `nil` when none of its test targets can be resolved
    /// against the generated projects.
    static func descriptor(
        for testPlan: TestPlan,
        graphTraverser: GraphTraversing,
        generatedProjects: [AbsolutePath: GeneratedProject],
        rootPath: AbsolutePath
    ) -> TestPlanDescriptor? {
        guard testPlan.isGenerated else { return nil }

        var testTargets: [TestPlanDescriptor.TestTarget] = []
        for testableTarget in testPlan.testTargets {
            guard let graphTarget = graphTraverser.target(
                path: testableTarget.target.projectPath,
                name: testableTarget.target.name
            ) else {
                continue
            }
            let projectPath = graphTarget.project.xcodeProjPath
            guard let generatedProject = generatedProjects[projectPath],
                  let pbxTarget = generatedProject.targets[graphTarget.target.name]
            else {
                continue
            }
            let containerRelativePath = projectPath.relative(to: rootPath).pathString
            testTargets.append(
                TestPlanDescriptor.TestTarget(
                    pbxTarget: pbxTarget,
                    containerPath: "container:\(containerRelativePath)",
                    isEnabled: !testableTarget.isSkipped
                )
            )
        }

        guard !testTargets.isEmpty else { return nil }

        return TestPlanDescriptor(path: testPlan.path, testTargets: testTargets)
    }

    /// Encodes a `TestPlanDescriptor` into the Xcode `.xctestplan` JSON format.
    ///
    /// - Note: Must be called after the owning `.xcodeproj` has been written so that `pbxTarget.uuid`
    ///   returns stable blueprint identifiers.
    static func encode(_ descriptor: TestPlanDescriptor) throws -> Data {
        let plan = XCTestPlanPayload(
            configurations: [
                XCTestPlanPayload.Configuration(
                    id: UUID(uuidString: "91BDB644-1AEA-4734-9E55-F6DA2F59DF74")!,
                    name: "Configuration 1",
                    options: [:]
                ),
            ],
            defaultOptions: [:],
            testTargets: descriptor.testTargets.map { target in
                XCTestPlanPayload.TestTarget(
                    enabled: target.isEnabled ? nil : false,
                    target: XCTestPlanPayload.TargetReference(
                        containerPath: target.containerPath,
                        identifier: target.pbxTarget.uuid,
                        name: target.pbxTarget.name
                    )
                )
            },
            version: 1
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(plan)
    }
}

private struct XCTestPlanPayload: Encodable {
    struct Configuration: Encodable {
        let id: UUID
        let name: String
        let options: [String: String]
    }

    struct TargetReference: Encodable {
        let containerPath: String
        let identifier: String
        let name: String
    }

    struct TestTarget: Encodable {
        let enabled: Bool?
        let target: TargetReference
    }

    let configurations: [Configuration]
    let defaultOptions: [String: String]
    let testTargets: [TestTarget]
    let version: Int
}
