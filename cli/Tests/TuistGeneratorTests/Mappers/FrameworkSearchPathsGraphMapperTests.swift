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

    private func appGraph(
        projectPath: AbsolutePath,
        targetName: String,
        dependencies: [GraphDependency]
    ) -> Graph {
        var graphDependencies: [GraphDependency: Set<GraphDependency>] = [
            .target(name: targetName, path: projectPath): Set(dependencies),
        ]
        for dependency in dependencies {
            graphDependencies[dependency] = Set()
        }
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            targets: [Target.test(name: targetName, product: .app)]
        )
        return Graph.test(projects: [projectPath: project], dependencies: graphDependencies)
    }

    func test_map_consolidatesFrameworksIntoSwiftSearchPath_whenManyPrecompiledFrameworks() async throws {
        // Given: many uniquely-named `.framework` artifacts, each in its own directory.
        let projectPath = try temporaryPath()
        let frameworks: [GraphDependency] = (0 ..< 25).map { i in
            .testFramework(
                path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).framework"),
                linking: .dynamic
            )
        }
        let graph = appGraph(projectPath: projectPath, targetName: "App", dependencies: frameworks)

        // When
        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try XCTUnwrap(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        XCTAssertTrue(
            arrayValue(settings.base["OTHER_CFLAGS"]).contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/App.resp\"")
        )
        XCTAssertTrue(
            arrayValue(settings.base["OTHER_LDFLAGS"]).contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/App.resp\"")
        )
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        XCTAssertTrue(otherSwiftFlags.contains("-F"))
        // `.framework` artifacts are linked into a single consolidated Swift search directory.
        XCTAssertTrue(otherSwiftFlags.contains("\"$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/App\""))
        XCTAssertFalse(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash0\""))
        // The precompiled paths live in the response file, not in FRAMEWORK_SEARCH_PATHS.
        XCTAssertFalse(arrayValue(settings.base["FRAMEWORK_SEARCH_PATHS"]).contains { $0.contains("/Frameworks/") })

        let responseFile = try XCTUnwrap(fileDescriptors(in: sideEffects).first { $0.path.pathString.hasSuffix("App.resp") })
        let contents = try XCTUnwrap(String(data: try XCTUnwrap(responseFile.contents), encoding: .utf8))
        XCTAssertTrue(contents.contains("-F\(projectPath.appending(components: "Frameworks", "hash0").pathString)"))

        let swiftSearchPathCleanupDescriptor = try XCTUnwrap(
            generatedFilesCleanupDescriptor(
                in: sideEffects,
                include: ["Swift/*/*.framework", "Swift/*/*.xcframework"]
            )
        )
        let swiftSearchPathDirectory = projectPath.appending(components: "Derived", "FrameworkSearchPaths")
        XCTAssertTrue(swiftSearchPathCleanupDescriptor.directories.contains(swiftSearchPathDirectory))
        XCTAssertTrue(
            swiftSearchPathCleanupDescriptor.activeFilesByDirectory[swiftSearchPathDirectory]?.contains(
                projectPath.appending(components: "Derived", "FrameworkSearchPaths", "Swift", "App", "Module0.framework")
            ) ?? false
        )

        XCTAssertTrue(
            symbolicLinkDescriptors(in: sideEffects).contains(
                SymbolicLinkDescriptor(
                    path: projectPath.appending(
                        components: "Derived",
                        "FrameworkSearchPaths",
                        "Swift",
                        "App",
                        "Module0.framework"
                    ),
                    destination: projectPath.appending(components: "Frameworks", "hash0", "Module0.framework")
                )
            )
        )
    }

    func test_map_keepsXCFrameworksInlineInSwiftFlagsAndDoesNotSymlinkThem_whenManyPrecompiledXCFrameworks() async throws {
        // Given: many uniquely-named `.xcframework` artifacts above the consolidation threshold.
        // `.xcframework` must NOT be symlinked into the Swift search directory: Swift's `-F` flag doesn't
        // resolve `.xcframework` bundles, and symlinking one exposes every platform slice to Xcode's
        // resource processing (regression: "Multiple commands produce" for per-slice resources).
        let projectPath = try temporaryPath()
        let xcframeworks: [GraphDependency] = (0 ..< 25).map { i in
            .testXCFramework(
                path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).xcframework"),
                linking: .dynamic
            )
        }
        let graph = appGraph(projectPath: projectPath, targetName: "App", dependencies: xcframeworks)

        // When
        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try XCTUnwrap(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        // Clang and the linker still get the paths via the response file.
        XCTAssertTrue(
            arrayValue(settings.base["OTHER_CFLAGS"]).contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/App.resp\"")
        )
        let responseFile = try XCTUnwrap(fileDescriptors(in: sideEffects).first { $0.path.pathString.hasSuffix("App.resp") })
        let contents = try XCTUnwrap(String(data: try XCTUnwrap(responseFile.contents), encoding: .utf8))
        XCTAssertTrue(contents.contains("-F\(projectPath.appending(components: "Frameworks", "hash0").pathString)"))

        // Swift receives every xcframework parent directory inline instead of a consolidated symlink directory.
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        XCTAssertTrue(otherSwiftFlags.contains("-F"))
        XCTAssertTrue(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash0\""))
        XCTAssertTrue(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash1\""))
        XCTAssertFalse(otherSwiftFlags.contains("\"$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/App\""))

        // No xcframework is ever represented as a symbolic link.
        XCTAssertTrue(symbolicLinkDescriptors(in: sideEffects).isEmpty)
        // And no Swift search-path symlink cleanup is emitted.
        XCTAssertNil(
            generatedFilesCleanupDescriptor(
                in: sideEffects,
                include: ["Swift/*/*.framework", "Swift/*/*.xcframework"]
            )
        )
    }

    func test_map_quotesResponseFileReference_whenTargetNameContainsWhitespace() async throws {
        // Given
        let projectPath = try temporaryPath()
        let xcframeworks: [GraphDependency] = (0 ..< 25).map { i in
            .testXCFramework(
                path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).xcframework"),
                linking: .dynamic
            )
        }
        let graph = appGraph(projectPath: projectPath, targetName: "Etsy Enterprise", dependencies: xcframeworks)

        // When
        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try XCTUnwrap(mappedGraph.projects[projectPath]?.targets["Etsy Enterprise"]?.settings)
        XCTAssertTrue(
            arrayValue(settings.base["OTHER_CFLAGS"])
                .contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/Etsy Enterprise.resp\"")
        )
        XCTAssertTrue(
            arrayValue(settings.base["OTHER_LDFLAGS"])
                .contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/Etsy Enterprise.resp\"")
        )
        XCTAssertTrue(sideEffects.contains { sideEffect in
            guard case let .file(file) = sideEffect else { return false }
            return file.path.pathString.hasSuffix("Derived/FrameworkSearchPaths/Etsy Enterprise.resp")
        })
    }

    func test_map_quotesSwiftFrameworkSearchPaths_whenTargetNameContainsWhitespace() async throws {
        // Given: `.framework` artifacts so the consolidated Swift search directory is created.
        let projectPath = try temporaryPath()
        let frameworks: [GraphDependency] = (0 ..< 25).map { i in
            .testFramework(
                path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).framework"),
                linking: .dynamic
            )
        }
        let graph = appGraph(projectPath: projectPath, targetName: "Notification Service", dependencies: frameworks)

        // When
        let (mappedGraph, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try XCTUnwrap(mappedGraph.projects[projectPath]?.targets["Notification Service"]?.settings)
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        XCTAssertTrue(otherSwiftFlags.contains("-F"))
        // The search path is quoted so Xcode does not word-split it into two tokens.
        XCTAssertTrue(
            otherSwiftFlags.contains("\"$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/Notification Service\"")
        )
        XCTAssertFalse(
            otherSwiftFlags.contains("$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/Notification Service")
        )
    }

    func test_map_deletesStaleFrameworkSearchPathResponseFiles() async throws {
        // Given
        let projectPath = try temporaryPath()
        let responseFileDirectory = projectPath.appending(components: "Derived", "FrameworkSearchPaths")
        let activeResponseFilePath = responseFileDirectory.appending(component: "App.resp")
        let staleResponseFilePath = responseFileDirectory.appending(component: "DeletedTarget.resp")

        let xcframeworks: [GraphDependency] = (0 ..< 25).map { i in
            .testXCFramework(
                path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).xcframework"),
                linking: .dynamic
            )
        }
        let graph = appGraph(projectPath: projectPath, targetName: "App", dependencies: xcframeworks)

        // When
        let (_, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let cleanupDescriptor = try XCTUnwrap(generatedFilesCleanupDescriptor(in: sideEffects))
        XCTAssertEqual(cleanupDescriptor.include, ["*.resp"])
        XCTAssertTrue(cleanupDescriptor.directories.contains(responseFileDirectory))
        XCTAssertEqual(cleanupDescriptor.activeFilesByDirectory[responseFileDirectory], Set([activeResponseFilePath]))
        XCTAssertFalse(cleanupDescriptor.activeFilesByDirectory[responseFileDirectory]?.contains(staleResponseFilePath) ?? false)
        XCTAssertTrue(
            sideEffects.contains { sideEffect in
                guard case let .file(fileDescriptor) = sideEffect else { return false }
                return fileDescriptor.path == activeResponseFilePath && fileDescriptor.state == .present
            }
        )
    }

    func test_map_keepsConflictingFrameworkNamesInline_whenConsolidatingSwiftSearchPaths() async throws {
        // Given: two `.framework` artifacts that share a basename conflict and stay inline, while the
        // remaining uniquely-named frameworks are linked into the consolidated Swift search directory.
        let projectPath = try temporaryPath()
        let frameworks: [GraphDependency] = [
            .testFramework(
                path: projectPath.appending(components: "Frameworks", "hash0", "Shared.framework"),
                linking: .dynamic
            ),
            .testFramework(
                path: projectPath.appending(components: "Frameworks", "hash1", "Shared.framework"),
                linking: .dynamic
            ),
        ] + (2 ..< 25).map { i in
            .testFramework(
                path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).framework"),
                linking: .dynamic
            ) as GraphDependency
        }
        let graph = appGraph(projectPath: projectPath, targetName: "App", dependencies: frameworks)

        // When
        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try XCTUnwrap(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        XCTAssertTrue(otherSwiftFlags.contains("\"$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/App\""))
        XCTAssertTrue(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash0\""))
        XCTAssertTrue(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash1\""))
        XCTAssertFalse(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash2\""))

        let symbolicLinks = symbolicLinkDescriptors(in: sideEffects)
        XCTAssertFalse(symbolicLinks.contains { $0.destination.basename == "Shared.framework" })
        XCTAssertTrue(symbolicLinks.contains { $0.destination.basename == "Module2.framework" })
    }

    func test_map_keepsFrameworkSearchPaths_whenFewPrecompiledFrameworks() async throws {
        // Given
        let projectPath = try temporaryPath()
        let xcframework: GraphDependency = .testXCFramework(
            path: projectPath.appending(components: "Frameworks", "hash0", "Module0.xcframework"),
            linking: .dynamic
        )
        let graph = appGraph(projectPath: projectPath, targetName: "App", dependencies: [xcframework])

        // When
        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try XCTUnwrap(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        XCTAssertTrue(arrayValue(settings.base["FRAMEWORK_SEARCH_PATHS"]).contains("$(SRCROOT)/Frameworks/hash0"))
        XCTAssertNil(settings.base["OTHER_CFLAGS"])
        XCTAssertTrue(fileDescriptors(in: sideEffects).isEmpty)
        let cleanupDescriptor = try XCTUnwrap(generatedFilesCleanupDescriptor(in: sideEffects))
        XCTAssertEqual(cleanupDescriptor.include, ["*.resp"])
        XCTAssertTrue(
            cleanupDescriptor.directories.contains(
                projectPath.appending(components: "Derived", "FrameworkSearchPaths")
            )
        )
    }

    private func arrayValue(_ value: SettingValue?) -> [String] {
        switch value {
        case let .array(values): return values
        case let .string(value): return [value]
        case nil: return []
        }
    }

    private func fileDescriptors(in sideEffects: [SideEffectDescriptor]) -> [FileDescriptor] {
        sideEffects.compactMap { sideEffect in
            guard case let .file(descriptor) = sideEffect else { return nil }
            return descriptor
        }
    }

    private func symbolicLinkDescriptors(in sideEffects: [SideEffectDescriptor]) -> [SymbolicLinkDescriptor] {
        sideEffects.compactMap { sideEffect in
            guard case let .symbolicLink(descriptor) = sideEffect else { return nil }
            return descriptor
        }
    }

    private func generatedFilesCleanupDescriptor(
        in sideEffects: [SideEffectDescriptor],
        include: [String] = ["*.resp"]
    ) -> GeneratedFilesCleanupDescriptor? {
        sideEffects.compactMap { sideEffect in
            guard case let .generatedFilesCleanup(descriptor) = sideEffect else { return nil }
            return descriptor.include == include ? descriptor : nil
        }.first
    }
}
