import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistGenerator

struct DynamicPackageStaticProductsGraphLinterTests {
    @Test(arguments: [GraphDependency.PackageProductType.runtimeDynamic, .runtimeDynamicEmbedded])
    func sharedDynamicProductsAreNotReportedAsDuplicateStatics(type: GraphDependency.PackageProductType) {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", product: .app)
        let framework = Target.test(name: "Framework", product: .framework)
        let project = Project.test(path: path, targets: [app, framework])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let frameworkDependency = GraphDependency.target(name: framework.name, path: path)
        let product = GraphDependency.packageProduct(path: path, product: "Dynamic", type: type)
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [appDependency: [frameworkDependency, product], frameworkDependency: [product]]
        )

        let issues = StaticProductsGraphLinter().lint(
            graphTraverser: GraphTraverser(graph: graph),
            configGeneratedProjectOptions: .default
        )

        #expect(issues.isEmpty)
    }
}
