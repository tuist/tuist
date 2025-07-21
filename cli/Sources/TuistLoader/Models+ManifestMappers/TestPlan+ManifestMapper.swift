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
        
        print("Mapping test plan at \(path)")

        return try TestPlan(
            path: path,
            testTargets: xcTestPlan.testTargets.map { testTarget in
                let testableTarget = try TestableTarget(
                    target: TargetReference(
                        projectPath: generatorPaths.resolve(path: .relativeToManifest(testTarget.target.projectPath))
                            .removingLastComponent(),
                        name: testTarget.target.name
                    ),
                    skipped: !testTarget.enabled
                )
                
                
                print("Mapped test plan target \(testTarget.target.name) at \(testTarget.target.projectPath): \(testableTarget)")

                return testableTarget
            },
            isDefault: isDefault
        )
    }
}
