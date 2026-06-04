import Foundation
import Path
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
import XCTest
@testable import TuistGenerator

final class FrameworkSearchPathsGraphMapperTests: TuistUnitTestCase {
    private var subject: FrameworkSearchPathsGraphMapper!

    override func setUp() {
        super.setUp()
        subject = FrameworkSearchPathsGraphMapper()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_map_consolidatesIntoResponseFile_whenManyPrecompiledFrameworks() throws {
        // Given
        let projectPath = try temporaryPath()
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: projectPath, sourceRootPath: projectPath, targets: [app])
        var xcframeworks: [GraphDependency] = []
        for i in 0 ..< 25 {
            xcframeworks.append(
                .testXCFramework(
                    path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).xcframework"),
                    linking: .dynamic
                )
            )
        }
        var dependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: "App", path: projectPath): Set(xcframeworks),
        ]
        for xcframework in xcframeworks {
            dependencies[xcframework] = Set()
        }
        let graph = Graph.test(projects: [projectPath: project], dependencies: dependencies)

        // When
        let (mappedGraph, sideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try XCTUnwrap(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        XCTAssertTrue(
            arrayValue(settings.base["OTHER_CFLAGS"]).contains("@$(SRCROOT)/Derived/FrameworkSearchPaths/App.resp")
        )
        XCTAssertTrue(
            arrayValue(settings.base["OTHER_LDFLAGS"]).contains("@$(SRCROOT)/Derived/FrameworkSearchPaths/App.resp")
        )
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        XCTAssertTrue(otherSwiftFlags.contains("-F"))
        XCTAssertTrue(otherSwiftFlags.contains("$(SRCROOT)/Frameworks/hash0"))
        // The precompiled paths live in the response file, not in FRAMEWORK_SEARCH_PATHS.
        XCTAssertFalse(arrayValue(settings.base["FRAMEWORK_SEARCH_PATHS"]).contains { $0.contains("/Frameworks/") })

        let responseFile = try XCTUnwrap(sideEffects.compactMap { sideEffect -> FileDescriptor? in
            guard case let .file(file) = sideEffect,
                  file.path.pathString.hasSuffix("Derived/FrameworkSearchPaths/App.resp")
            else { return nil }
            return file
        }.first)
        let contents = try XCTUnwrap(String(data: try XCTUnwrap(responseFile.contents), encoding: .utf8))
        XCTAssertTrue(contents.contains("-F\(projectPath.appending(components: "Frameworks", "hash0").pathString)"))
    }

    func test_map_keepsFrameworkSearchPaths_whenFewPrecompiledFrameworks() throws {
        // Given
        let projectPath = try temporaryPath()
        let app = Target.test(name: "App", product: .app)
        let project = Project.test(path: projectPath, sourceRootPath: projectPath, targets: [app])
        let xcframework: GraphDependency = .testXCFramework(
            path: projectPath.appending(components: "Frameworks", "hash0", "Module0.xcframework"),
            linking: .dynamic
        )
        let graph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): Set([xcframework]),
                xcframework: Set(),
            ]
        )

        // When
        let (mappedGraph, sideEffects, _) = try subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try XCTUnwrap(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        XCTAssertTrue(arrayValue(settings.base["FRAMEWORK_SEARCH_PATHS"]).contains("$(SRCROOT)/Frameworks/hash0"))
        XCTAssertNil(settings.base["OTHER_CFLAGS"])
        XCTAssertTrue(sideEffects.isEmpty)
    }

    private func arrayValue(_ value: SettingValue?) -> [String] {
        switch value {
        case let .array(values): return values
        case let .string(value): return [value]
        case nil: return []
        }
    }
}
