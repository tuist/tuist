import Foundation
import TSCBasic
import TuistGraph

extension TestPlan {
    init(path: AbsolutePath, isDefault: Bool, generatorPaths: GeneratorPaths) throws {
        let jsonDecoder = JSONDecoder()
        let testPlanData = try Data(contentsOf: path.asURL)
        let xcTestPlan = try jsonDecoder.decode(XCTestPlan.self, from: testPlanData)

        try self.init(
            path: path,
            testTargets: xcTestPlan.testTargets.map { testTarget in
                try TestableTarget(
                    target: TargetReference(
                        projectPath: generatorPaths.resolve(path: .relativeToRoot(testTarget.target.projectPath))
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
 
