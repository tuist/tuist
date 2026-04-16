import FileSystem
import Foundation
import Path
import XcodeGraph

extension TestPlan {
    static func from(
        path: AbsolutePath,
        isDefault: Bool,
        generatorPaths: GeneratorPaths
    ) async throws -> TestPlan {
        let fileSystem = FileSystem()
        let xcTestPlan: XCTestPlan = try await fileSystem.readJSONFile(at: path, decoder: JSONDecoder())

        return try TestPlan(
            path: path,
            testTargets: xcTestPlan.testTargets.map { testTarget in
                let projectPath: AbsolutePath = if testTarget.target.projectPath.isEmpty {
                    generatorPaths.manifestDirectory
                } else {
                    try generatorPaths.resolve(path: .relativeToManifest(testTarget.target.projectPath))
                        .removingLastComponent()
                }
                return try TestableTarget(
                    target: TargetReference(
                        projectPath: projectPath,
                        name: testTarget.target.name
                    ),
                    skipped: !testTarget.enabled
                )
            },
            isDefault: isDefault
        )
    }
}
