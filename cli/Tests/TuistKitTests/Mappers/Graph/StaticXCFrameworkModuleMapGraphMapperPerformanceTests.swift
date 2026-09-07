import Mockable
import Path
import Testing
import TuistCore
import TuistLoader
import XcodeGraph
@testable import TuistKit

struct StaticXCFrameworkModuleMapGraphMapperPerformanceTests {
    @Test func map_scales_linearly_when_surviving_targets_share_cached_dependencies() async throws {
        let manifestFilesLocator = MockManifestFilesLocating()
        given(manifestFilesLocator).locatePackageManifest(at: .any).willReturn(nil)
        let subject = StaticXCFrameworkModuleMapGraphMapper(manifestFilesLocator: manifestFilesLocator)
        let small = try fixture(cachedTargetCount: 150, survivingTargetCount: 40)
        let large = try fixture(cachedTargetCount: 1500, survivingTargetCount: 400)

        // Warm runtime metadata, not traversal caches: map creates new traversers on every call.
        _ = try await measure(subject, fixture: small)
        _ = try await measure(subject, fixture: large)
        var smallSamples: [Double] = []
        var largeSamples: [Double] = []
        for iteration in 0 ..< 5 {
            // Alternate order to reduce bias from thermal changes and background load.
            if iteration.isMultiple(of: 2) {
                smallSamples.append(try await measure(subject, fixture: small))
                largeSamples.append(try await measure(subject, fixture: large))
            } else {
                largeSamples.append(try await measure(subject, fixture: large))
                smallSamples.append(try await measure(subject, fixture: small))
            }
        }
        let smallMedian = smallSamples.sorted()[2]
        let largeMedian = largeSamples.sorted()[2]
        let growth = largeMedian / smallMedian
        print("Cached graph mapper: small=\(smallMedian)s, large=\(largeMedian)s, growth=\(growth)x")

        // Both vertices and edges grow 10x. Allow 3x headroom over linear growth;
        // a separate source-graph walk per survivor (PR #12807) grows roughly 100x.
        #expect(
            growth < 30,
            "10x graph grew \(growth)x: small=\(smallSamples), large=\(largeSamples). Check per-target traversal caching."
        )
    }

    private struct Fixture {
        let graph: Graph
        let environment: MapperEnvironment
        let expectedSearchPaths: SettingValue
    }

    private func measure(
        _ subject: StaticXCFrameworkModuleMapGraphMapper,
        fixture: Fixture
    ) async throws -> Double {
        let clock = ContinuousClock()
        let start = clock.now
        let (mapped, sideEffects, _) = try await subject.map(graph: fixture.graph, environment: fixture.environment)
        let duration = start.duration(to: clock.now)

        // Keep correctness checks and fixture construction outside the timed region. A no-op
        // mapper, or a walker that stops recovering either module flavour, must not pass.
        let project = try #require(mapped.projects[fixture.graph.path])
        #expect(project.targets.count == fixture.graph.projects[fixture.graph.path]?.targets.count)
        for target in project.targets.values {
            #expect(target.settings?.base["FRAMEWORK_SEARCH_PATHS[sdk=iphoneos*]"] == fixture.expectedSearchPaths)
        }
        #expect(sideEffects.isEmpty)
        return Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }

    private func fixture(cachedTargetCount: Int, survivingTargetCount: Int) throws -> Fixture {
        let path = try AbsolutePath(validating: "/mapper-performance")
        let width = 50
        let cachedTargets = (0 ..< cachedTargetCount).map { Target.test(name: "Cached\($0)", product: .framework) }
        let survivingTargets = (0 ..< survivingTargetCount).map { Target.test(name: "Consumer\($0)", product: .app) }
        let cachedNodes = cachedTargets.map { GraphDependency.target(name: $0.name, path: path) }
        let cachedBinary = GraphDependency.testXCFramework(path: path.appending(component: "Cached.xcframework"))
        let libraries: [XCFrameworkInfoPlist.Library] = [
            .test(identifier: "ios-arm64", path: try RelativePath(validating: "Vendor.framework")),
        ]
        let objc = GraphDependency.testXCFramework(
            path: path.appending(component: "ObjC.xcframework"),
            infoPlist: .test(libraries: libraries),
            linking: .static,
            moduleMaps: [path.appending(components: "ObjC.xcframework", "module.modulemap")]
        )
        let swift = GraphDependency.testXCFramework(
            path: path.appending(component: "Swift.xcframework"),
            infoPlist: .test(libraries: libraries),
            linking: .static,
            swiftModules: [path.appending(components: "Swift.xcframework", "Vendor.swiftmodule")]
        )

        // A layered, shared DAG: every consumer reaches the same cached source targets.
        // Cache substitution removes those targets and the edges to the vendor modules.
        var sourceDependencies: [GraphDependency: Set<GraphDependency>] = [:]
        for index in cachedNodes.indices {
            let nextLayer = (index / width + 1) * width
            if nextLayer < cachedTargetCount {
                sourceDependencies[cachedNodes[index]] = Set((0 ..< 3).map {
                    cachedNodes[nextLayer + (index + $0) % width]
                })
            } else {
                sourceDependencies[cachedNodes[index]] = [objc, swift]
            }
        }
        var substitutedDependencies: [GraphDependency: Set<GraphDependency>] = [:]
        for target in survivingTargets {
            let node = GraphDependency.target(name: target.name, path: path)
            sourceDependencies[node] = Set(cachedNodes.prefix(width))
            substitutedDependencies[node] = [cachedBinary]
        }
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = .test(
            path: path,
            projects: [path: .test(path: path, targets: survivingTargets + cachedTargets)],
            dependencies: sourceDependencies
        )
        return Fixture(
            graph: .test(
                path: path,
                projects: [path: .test(path: path, targets: survivingTargets)],
                dependencies: substitutedDependencies
            ),
            environment: environment,
            expectedSearchPaths: .array([
                "$(inherited)",
                "\"$(SRCROOT)/ObjC.xcframework/ios-arm64\"",
                "\"$(SRCROOT)/Swift.xcframework/ios-arm64\"",
            ])
        )
    }
}
