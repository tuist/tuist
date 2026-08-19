import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistAlert
import TuistEnvironment
import XcodeGraph
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistTesting

struct FrameworkSearchPathsGraphMapperTests {
    private let subject = FrameworkSearchPathsGraphMapper()

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

    @Test(.inTemporaryDirectory)
    func consolidatesFrameworksIntoSwiftSearchPathWhenManyPrecompiledFrameworks() async throws {
        // Given: many uniquely-named `.framework` artifacts, each in its own directory.
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
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
        let settings = try #require(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        #expect(
            arrayValue(settings.base["OTHER_CFLAGS"]).contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/App.resp\"")
        )
        #expect(
            arrayValue(settings.base["OTHER_LDFLAGS"]).contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/App.resp\"")
        )
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        #expect(otherSwiftFlags.contains("-F"))
        // `.framework` artifacts are linked into a single consolidated Swift search directory.
        #expect(otherSwiftFlags.contains("\"$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/App\""))
        #expect(!otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash0\""))
        // The precompiled paths live in the response file, not in FRAMEWORK_SEARCH_PATHS.
        let frameworkSearchPaths = arrayValue(settings.base["FRAMEWORK_SEARCH_PATHS"])
        #expect(!frameworkSearchPaths.contains(where: { $0.contains("/Frameworks/") }))

        let responseFile = try #require(
            fileDescriptors(in: sideEffects).first { $0.path.pathString.hasSuffix("App.resp") }
        )
        let responseData = try #require(responseFile.contents)
        let contents = try #require(String(data: responseData, encoding: .utf8))
        #expect(contents.contains("-F\(projectPath.appending(components: "Frameworks", "hash0").pathString)"))

        let swiftSearchPathCleanupDescriptor = try #require(
            generatedFilesCleanupDescriptor(
                in: sideEffects,
                include: ["Swift/*/*.framework", "Swift/*/*.xcframework"]
            )
        )
        let swiftSearchPathDirectory = projectPath.appending(components: "Derived", "FrameworkSearchPaths")
        #expect(swiftSearchPathCleanupDescriptor.directories.contains(swiftSearchPathDirectory))
        #expect(
            swiftSearchPathCleanupDescriptor.activeFilesByDirectory[swiftSearchPathDirectory]?.contains(
                projectPath.appending(components: "Derived", "FrameworkSearchPaths", "Swift", "App", "Module0.framework")
            ) ?? false
        )

        #expect(
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

    @Test(.inTemporaryDirectory)
    func keepsXCFrameworksInlineInSwiftFlagsAndDoesNotSymlinkThemWhenManyPrecompiledXCFrameworks() async throws {
        // Given: many uniquely-named `.xcframework` artifacts above the consolidation threshold.
        // `.xcframework` must NOT be symlinked into the Swift search directory: Swift's `-F` flag doesn't
        // resolve `.xcframework` bundles, and symlinking one exposes every platform slice to Xcode's
        // resource processing (regression: "Multiple commands produce" for per-slice resources).
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
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
        let settings = try #require(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        // Clang and the linker still get the paths via the response file.
        #expect(
            arrayValue(settings.base["OTHER_CFLAGS"]).contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/App.resp\"")
        )
        let responseFile = try #require(
            fileDescriptors(in: sideEffects).first { $0.path.pathString.hasSuffix("App.resp") }
        )
        let responseData = try #require(responseFile.contents)
        let contents = try #require(String(data: responseData, encoding: .utf8))
        #expect(contents.contains("-F\(projectPath.appending(components: "Frameworks", "hash0").pathString)"))

        // Swift receives every xcframework parent directory inline instead of a consolidated symlink directory.
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        #expect(otherSwiftFlags.contains("-F"))
        #expect(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash0\""))
        #expect(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash1\""))
        #expect(!otherSwiftFlags.contains("\"$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/App\""))

        // No xcframework is ever represented as a symbolic link.
        #expect(symbolicLinkDescriptors(in: sideEffects).isEmpty)

        // A Swift search-path cleanup descriptor is still emitted with an empty active-file set so that
        // stale `.xcframework` links left behind by older Tuist versions are removed on the next generate.
        let symlinkCleanup = try #require(
            generatedFilesCleanupDescriptor(
                in: sideEffects,
                include: ["Swift/*/*.framework", "Swift/*/*.xcframework"]
            )
        )
        let swiftSearchPathDirectory = projectPath.appending(components: "Derived", "FrameworkSearchPaths")
        #expect(symlinkCleanup.directories.contains(swiftSearchPathDirectory))
        #expect((symlinkCleanup.activeFilesByDirectory[swiftSearchPathDirectory] ?? []).isEmpty)
    }

    @Test(.inTemporaryDirectory)
    func quotesResponseFileReferenceWhenTargetNameContainsWhitespace() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
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
        let settings = try #require(mappedGraph.projects[projectPath]?.targets["Etsy Enterprise"]?.settings)
        #expect(
            arrayValue(settings.base["OTHER_CFLAGS"])
                .contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/Etsy Enterprise.resp\"")
        )
        #expect(
            arrayValue(settings.base["OTHER_LDFLAGS"])
                .contains("\"@$(SRCROOT)/Derived/FrameworkSearchPaths/Etsy Enterprise.resp\"")
        )
        let hasResponseFile = sideEffects.contains { sideEffect in
            if case let .file(file) = sideEffect {
                return file.path.pathString.hasSuffix("Derived/FrameworkSearchPaths/Etsy Enterprise.resp")
            }
            return false
        }
        #expect(hasResponseFile)
    }

    @Test(.inTemporaryDirectory)
    func quotesSwiftFrameworkSearchPathsWhenTargetNameContainsWhitespace() async throws {
        // Given: `.framework` artifacts so the consolidated Swift search directory is created.
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
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
        let settings = try #require(mappedGraph.projects[projectPath]?.targets["Notification Service"]?.settings)
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        #expect(otherSwiftFlags.contains("-F"))
        // The search path is quoted so Xcode does not word-split it into two tokens.
        #expect(
            otherSwiftFlags.contains("\"$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/Notification Service\"")
        )
        #expect(
            !otherSwiftFlags.contains("$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/Notification Service")
        )
    }

    @Test(.inTemporaryDirectory)
    func deletesStaleFrameworkSearchPathResponseFiles() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
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
        let cleanupDescriptor = try #require(generatedFilesCleanupDescriptor(in: sideEffects))
        #expect(cleanupDescriptor.include == ["*.resp"])
        #expect(cleanupDescriptor.directories.contains(responseFileDirectory))
        #expect(cleanupDescriptor.activeFilesByDirectory[responseFileDirectory] == Set([activeResponseFilePath]))
        #expect(!(cleanupDescriptor.activeFilesByDirectory[responseFileDirectory]?.contains(staleResponseFilePath) ?? true))
        let hasResponseFile = sideEffects.contains { sideEffect in
            if case let .file(fileDescriptor) = sideEffect {
                return fileDescriptor.path == activeResponseFilePath && fileDescriptor.state == .present
            }
            return false
        }
        #expect(hasResponseFile)
    }

    @Test(.inTemporaryDirectory)
    func keepsConflictingFrameworkNamesInlineWhenConsolidatingSwiftSearchPaths() async throws {
        // Given: two `.framework` artifacts that share a basename conflict and stay inline, while the
        // remaining uniquely-named frameworks are linked into the consolidated Swift search directory.
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        var frameworks: [GraphDependency] = [
            .testFramework(
                path: projectPath.appending(components: "Frameworks", "hash0", "Shared.framework"),
                linking: .dynamic
            ),
            .testFramework(
                path: projectPath.appending(components: "Frameworks", "hash1", "Shared.framework"),
                linking: .dynamic
            ),
        ]
        frameworks += (2 ..< 25).map { i in
            GraphDependency.testFramework(
                path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).framework"),
                linking: .dynamic
            )
        }
        let graph = appGraph(projectPath: projectPath, targetName: "App", dependencies: frameworks)

        // When
        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try #require(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        let otherSwiftFlags = arrayValue(settings.base["OTHER_SWIFT_FLAGS"])
        #expect(otherSwiftFlags.contains("\"$(SRCROOT)/Derived/FrameworkSearchPaths/Swift/App\""))
        #expect(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash0\""))
        #expect(otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash1\""))
        #expect(!otherSwiftFlags.contains("\"$(SRCROOT)/Frameworks/hash2\""))

        let symbolicLinks = symbolicLinkDescriptors(in: sideEffects)
        #expect(!symbolicLinks.contains { $0.destination.basename == "Shared.framework" })
        #expect(symbolicLinks.contains { $0.destination.basename == "Module2.framework" })
    }

    @Test(.inTemporaryDirectory)
    func keepsFrameworkSearchPathsWhenFewPrecompiledFrameworks() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let xcframework = GraphDependency.testXCFramework(
            path: projectPath.appending(components: "Frameworks", "hash0", "Module0.xcframework"),
            linking: .dynamic
        )
        let graph = appGraph(projectPath: projectPath, targetName: "App", dependencies: [xcframework])

        // When
        let (mappedGraph, sideEffects, _) = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let settings = try #require(mappedGraph.projects[projectPath]?.targets["App"]?.settings)
        #expect(arrayValue(settings.base["FRAMEWORK_SEARCH_PATHS"]).contains("$(SRCROOT)/Frameworks/hash0"))
        #expect(settings.base["OTHER_CFLAGS"] == nil)
        #expect(fileDescriptors(in: sideEffects).isEmpty)
        let cleanupDescriptor = try #require(generatedFilesCleanupDescriptor(in: sideEffects))
        #expect(cleanupDescriptor.include == ["*.resp"])
        #expect(
            cleanupDescriptor.directories.contains(
                projectPath.appending(components: "Derived", "FrameworkSearchPaths")
            )
        )
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func warnsWhenTargetResolvesSeveralArtifactsProvidingTheSameFramework() async throws {
        // Given: two differently named containers that both ship `Foo.framework`. What a target imports is the
        // framework inside the container, not the container, so these collide even though nothing about their
        // own names matches.
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let vendored = projectPath.appending(components: "vendor", "VendoredFoo.xcframework")
        let cached = projectPath.appending(components: "cache", "Foo.xcframework")
        let graph = appGraph(
            projectPath: projectPath,
            targetName: "App",
            dependencies: [
                .testXCFramework(path: vendored, infoPlist: xcframeworkInfoPlist(framework: "Foo"), linking: .dynamic),
                .testXCFramework(path: cached, infoPlist: xcframeworkInfoPlist(framework: "Foo"), linking: .dynamic),
            ]
        )

        // When
        _ = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let warnings = AlertController.current.warnings().map(\.message).map { $0.plain() }
        #expect(warnings.count == 1)
        let warning = try #require(warnings.first)
        #expect(warning.contains("'App'"))
        #expect(warning.contains("'Foo'"))
        #expect(warning.contains(cached.pathString))
        #expect(warning.contains(vendored.pathString))
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func warnsWhenAFrameworkCollidesWithAnXCFrameworkContainingIt() async throws {
        // Given: a plain `Foo.framework` alongside an `.xcframework` whose slices ship `Foo.framework`.
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let framework = projectPath.appending(components: "vendor", "Foo.framework")
        let xcframework = projectPath.appending(components: "cache", "Foo.xcframework")
        let graph = appGraph(
            projectPath: projectPath,
            targetName: "App",
            dependencies: [
                .testFramework(path: framework, linking: .dynamic),
                .testXCFramework(path: xcframework, infoPlist: xcframeworkInfoPlist(framework: "Foo"), linking: .dynamic),
            ]
        )

        // When
        _ = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let warnings = AlertController.current.warnings().map(\.message).map { $0.plain() }
        #expect(warnings.count == 1)
        let warning = try #require(warnings.first)
        #expect(warning.contains("'Foo'"))
        #expect(warning.contains(framework.pathString))
        #expect(warning.contains(xcframework.pathString))
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func doesNotWarnWhenIdenticallyNamedContainersShipDifferentFrameworks() async throws {
        // Given: two containers that share a name but ship unrelated frameworks. Nothing competes for a
        // framework name, so there is nothing for the search path order to decide.
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let graph = appGraph(
            projectPath: projectPath,
            targetName: "App",
            dependencies: [
                .testXCFramework(
                    path: projectPath.appending(components: "vendor", "Shared.xcframework"),
                    infoPlist: xcframeworkInfoPlist(framework: "Analytics"),
                    linking: .dynamic
                ),
                .testXCFramework(
                    path: projectPath.appending(components: "cache", "Shared.xcframework"),
                    infoPlist: xcframeworkInfoPlist(framework: "Networking"),
                    linking: .dynamic
                ),
            ]
        )

        // When
        _ = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(AlertController.current.warnings().isEmpty)
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func reportsEachAmbiguousFrameworkNameOnceAcrossTargets() async throws {
        // Given: the same pair of colliding artifacts on two targets. The ambiguity is a property of the
        // artifacts, so it is reported once no matter how many targets resolve it.
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let vendored = GraphDependency.testXCFramework(
            path: projectPath.appending(components: "vendor", "Foo.xcframework"),
            infoPlist: xcframeworkInfoPlist(framework: "Foo"),
            linking: .dynamic
        )
        let cached = GraphDependency.testXCFramework(
            path: projectPath.appending(components: "cache", "Foo.xcframework"),
            infoPlist: xcframeworkInfoPlist(framework: "Foo"),
            linking: .dynamic
        )
        let project = Project.test(
            path: projectPath,
            sourceRootPath: projectPath,
            targets: [
                Target.test(name: "App", product: .app),
                Target.test(name: "Feature", product: .framework),
            ]
        )
        let graph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "App", path: projectPath): Set([vendored, cached]),
                .target(name: "Feature", path: projectPath): Set([vendored, cached]),
                vendored: Set(),
                cached: Set(),
            ]
        )

        // When
        _ = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        let warnings = AlertController.current.warnings().map(\.message).map { $0.plain() }
        #expect(warnings.count == 1)
        let warning = try #require(warnings.first)
        #expect(warning.contains("'App'"))
        #expect(warning.contains("1 other target"))
    }

    @Test(.inTemporaryDirectory, .withScopedAlertController())
    func doesNotWarnWhenFrameworkNamesAreUnique() async throws {
        // Given
        let projectPath = try #require(FileSystem.temporaryTestDirectory)
        let graph = appGraph(
            projectPath: projectPath,
            targetName: "App",
            dependencies: (0 ..< 25).map { i in
                .testXCFramework(
                    path: projectPath.appending(components: "Frameworks", "hash\(i)", "Module\(i).xcframework"),
                    infoPlist: xcframeworkInfoPlist(framework: "Module\(i)"),
                    linking: .dynamic
                )
            }
        )

        // When
        _ = try await subject.map(graph: graph, environment: MapperEnvironment())

        // Then
        #expect(AlertController.current.warnings().isEmpty)
    }

    /// The framework search paths of a target that resolves a cached `Foo.xcframework` and a vendored one,
    /// with the cache stored under `cacheRoot`.
    private func searchPathOrder(cacheRoot: String, vendored: String) async throws -> [String] {
        let mockEnvironment = try #require(Environment.mocked)
        mockEnvironment.cacheDirectory = try AbsolutePath(validating: cacheRoot)

        let sourceRoot = try AbsolutePath(validating: "/repo/Project")
        let cached = GraphDependency.testXCFramework(
            // Content-addressed, so the path below the cache root is the same on every machine.
            path: try AbsolutePath(validating: "\(cacheRoot)/binaries/8f2c1d/Foo.xcframework"),
            infoPlist: xcframeworkInfoPlist(framework: "Foo"),
            linking: .dynamic
        )
        let vendored = GraphDependency.testXCFramework(
            path: try AbsolutePath(validating: "\(vendored)/Foo.xcframework"),
            infoPlist: xcframeworkInfoPlist(framework: "Foo"),
            linking: .dynamic
        )
        let target = Target.test(name: "App", product: .app)
        let project = Project.test(path: sourceRoot, sourceRootPath: sourceRoot, targets: [target])
        let graph = Graph.test(
            projects: [sourceRoot: project],
            dependencies: [
                .target(name: "App", path: sourceRoot): Set([cached, vendored]),
                cached: Set(),
                vendored: Set(),
            ]
        )

        let (mapped, _, _) = try await subject.map(graph: graph, environment: MapperEnvironment())
        let settings = try #require(mapped.projects[sourceRoot]?.targets["App"]?.settings)
        guard case let .array(values) = settings.base["FRAMEWORK_SEARCH_PATHS"] else { return [] }
        return values.filter { $0 != "$(inherited)" }
    }

    @Test(.withMockedEnvironment(), .withScopedAlertController())
    func ordersACachedArtifactAheadOfAVendoredOneWhereverTheCacheIsStored() async throws {
        // Given: the same graph on two machines whose cache directories sort to opposite sides of the
        // vendored artifact's path. Ordering on the rendered value put the cached artifact first on one and
        // second on the other, which decides which `Foo` the target compiles against.
        let vendored = "/Users/nate/vendor"

        // When
        let alice = try await searchPathOrder(cacheRoot: "/Users/alice/cache", vendored: vendored)
        let zoe = try await searchPathOrder(cacheRoot: "/Users/zoe/cache", vendored: vendored)

        // Then: the cached artifact leads on both, so both resolve the same `Foo`.
        #expect(alice.first?.contains("/Users/alice/cache/binaries/8f2c1d") == true)
        #expect(zoe.first?.contains("/Users/zoe/cache/binaries/8f2c1d") == true)
        #expect(alice.last == "$(SRCROOT)/../../Users/nate/vendor")
        #expect(zoe.last == "$(SRCROOT)/../../Users/nate/vendor")
        #expect(alice.count == 2)
        #expect(zoe.count == 2)
    }

    private func xcframeworkInfoPlist(framework: String) -> XCFrameworkInfoPlist {
        .test(
            libraries: [
                .test(
                    identifier: "ios-arm64",
                    // swiftlint:disable:next force_try
                    path: try! RelativePath(validating: "ios-arm64/\(framework).framework")
                ),
            ]
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
            if case let .file(descriptor) = sideEffect { return descriptor }
            return nil
        }
    }

    private func symbolicLinkDescriptors(in sideEffects: [SideEffectDescriptor]) -> [SymbolicLinkDescriptor] {
        sideEffects.compactMap { sideEffect in
            if case let .symbolicLink(descriptor) = sideEffect { return descriptor }
            return nil
        }
    }

    private func generatedFilesCleanupDescriptor(
        in sideEffects: [SideEffectDescriptor],
        include: [String] = ["*.resp"]
    ) -> GeneratedFilesCleanupDescriptor? {
        sideEffects.compactMap { sideEffect in
            if case let .generatedFilesCleanup(descriptor) = sideEffect {
                return descriptor.include == include ? descriptor : nil
            }
            return nil
        }.first
    }
}
