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
                try TestableTarget(
                    target: TargetReference(
                        projectPath: generatorPaths.resolve(path: .relativeToManifest(testTarget.target.projectPath))
                            .removingLastComponent(),
                        name: testTarget.target.name
                    ),
                    skipped: !testTarget.enabled
                )
            },
            isDefault: isDefault
        )
    }
}
