import Path
import Testing
import TuistCore
import XcodeGraph
import XcodeProj
@testable import TuistGenerator

struct LinkGeneratorHostedPackageTests {
    @Test(arguments: [GraphDependency.PackageProductType.runtimeDynamic, .runtimeDynamicEmbedded])
    func hostedTestsLinkDynamicProductsWithoutEmbeddingThem(type: GraphDependency.PackageProductType) throws {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: path, targets: [app, tests])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        let product = GraphDependency.packageProduct(path: path, product: "DynamicProduct", type: type)
        let graph = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [appDependency: [product], testsDependency: [appDependency, product]]
        )
        let traverser = GraphTraverser(graph: graph)
        let subject = LinkGenerator()
        let pbxproj = PBXProj()
        let pbxTarget = PBXNativeTarget(name: tests.name)
        pbxproj.add(object: pbxTarget)

        try subject.generateLinkingPhase(
            target: tests,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: ProjectFileElements(),
            path: path,
            graphTraverser: traverser
        )
        try subject.generateEmbedPhase(
            target: tests,
            pbxTarget: pbxTarget,
            pbxproj: pbxproj,
            fileElements: ProjectFileElements(),
            sourceRootPath: path,
            path: path,
            graphTraverser: traverser
        )

        #expect(pbxTarget.packageProductDependencies?.map(\.productName) == ["DynamicProduct"])
        #expect(try pbxTarget.frameworksBuildPhase()?.files?.map { $0.product?.productName } == ["DynamicProduct"])
        #expect(pbxTarget.embedFrameworksBuildPhases().flatMap { $0.files ?? [] }.isEmpty)
    }
}
