import Path
import Testing
import TuistCache
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
        let unlinkedPlain = Target.test(name: "UnlinkedPlain", product: .framework, productName: "UnlinkedPlain")
        let assets = Target.test(name: "Assets", product: .bundle, productName: "Assets")
        let project = Project.test(path: projectPath, targets: [app, lib, plain, unlinked, unlinkedPlain, assets])
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
            "UnlinkedPlain": .test(name: "UnlinkedPlain", hash: "up", source: .local, cacheCategory: .binaries),
            "Assets": .test(name: "Assets", hash: "as", source: .local, cacheCategory: .binaries),
        ]]
        // A hit the run does not link has no binary to read; its key tells how it was built.
        let subhashes: [String: TargetContentHashSubhashes] = [
            "u": .test(additionalStrings: ["Debug", CacheGraphContentHasher.coverageDimension]),
            "up": .test(additionalStrings: ["Debug"]),
            // Keyed on coverage like every repository target, but a warm never instruments a bundle.
            "as": .test(additionalStrings: ["Debug", CacheGraphContentHasher.coverageDimension]),
        ]

        let annotated = CoverageInstrumentation.annotate(
            items,
            graph: graph,
            generatedGraph: generated,
            subhashes: subhashes
        ) { path in
            path == "/cache/Lib.xcframework/ios-arm64/Lib.framework/Lib"
        }

        let byName = try #require(annotated[projectPath])
        #expect(byName["App"]?.instrumented == nil)
        #expect(byName["Lib"]?.instrumented == true)
        #expect(byName["Plain"]?.instrumented == false)
        #expect(byName["Unlinked"]?.instrumented == true)
        #expect(byName["UnlinkedPlain"]?.instrumented == nil)
        #expect(byName["Assets"]?.instrumented == nil)
        #expect(byName["Lib"]?.hash == "l")
        #expect(byName["Lib"]?.source == .remote)
    }
}
