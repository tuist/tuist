import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph
@testable import TuistKit

struct CoverageInstrumentationTests {
    @Test func tellsTheHitsWhoseBinariesCarryCoverageCounters() throws {
        let projectPath = try AbsolutePath(validating: "/repo")
        let app = Target.test(name: "App", product: .app)
        let lib = Target.test(name: "Lib", product: .staticFramework, productName: "Lib")
        let plain = Target.test(name: "Plain", product: .staticFramework, productName: "Plain")
        let unlinked = Target.test(name: "Unlinked", product: .framework, productName: "Unlinked")
        let project = Project.test(path: projectPath, targets: [app, lib, plain, unlinked])
        let graph = Graph.test(projects: [projectPath: project])
        let xcframework = { (name: String) throws in
            GraphDependency.XCFramework(
                path: try AbsolutePath(validating: "/cache/\(name).xcframework"),
                infoPlist: .test(libraries: [
                    .test(identifier: "ios-arm64", path: try RelativePath(validating: "\(name).framework"), platform: .iOS),
                ]),
                linking: .static,
                mergeable: false,
                status: .required,
                swiftModules: [],
                moduleMaps: []
            )
        }
        let generated = Graph.test(
            projects: [projectPath: Project.test(path: projectPath, targets: [app])],
            dependencies: [
                .target(name: "App", path: projectPath): [
                    .xcframework(try xcframework("Lib")),
                    .xcframework(try xcframework("Plain")),
                ],
            ]
        )
        let items: [AbsolutePath: [String: CacheItem]] = [projectPath: [
            "App": .test(name: "App", hash: "a", source: .miss, cacheCategory: .binaries),
            "Lib": .test(name: "Lib", hash: "l", source: .remote, cacheCategory: .binaries),
            "Plain": .test(name: "Plain", hash: "p", source: .local, cacheCategory: .binaries),
            "Unlinked": .test(name: "Unlinked", hash: "u", source: .local, cacheCategory: .binaries),
        ]]

        let annotated = CoverageInstrumentation.annotate(items, graph: graph, generatedGraph: generated) { path in
            path == "/cache/Lib.xcframework/ios-arm64/Lib.framework/Lib"
        }

        let byName = try #require(annotated[projectPath])
        #expect(byName["App"]?.instrumented == nil)
        #expect(byName["Lib"]?.instrumented == true)
        #expect(byName["Plain"]?.instrumented == false)
        #expect(byName["Unlinked"]?.instrumented == nil)
        #expect(byName["Lib"]?.hash == "l")
        #expect(byName["Lib"]?.source == .remote)
    }
}
