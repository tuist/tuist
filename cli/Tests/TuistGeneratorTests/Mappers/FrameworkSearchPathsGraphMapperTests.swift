import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
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
