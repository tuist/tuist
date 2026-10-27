import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
@testable import TuistCache

struct SwiftPackageHeadersExporterTests {
    enum ModuleKind: CaseIterable {
        case custom, umbrellaHeader, directory
    }

    enum ArtifactKind: CaseIterable {
        case library, framework, versionedFramework
    }

    @Test(.inTemporaryDirectory, arguments: ModuleKind.allCases, ArtifactKind.allCases)
    func exportedHeadersCompileWithoutOriginalCheckout(kind: ModuleKind, artifactKind: ArtifactKind) async throws {
        let framework = artifactKind != .library
        let directoryModule = kind == .directory
        let temporary = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let root = temporary.appending(component: "source")
        let include = root.appending(component: "include")
        let nested = include.appending(component: "nested")
        try await fileSystem.makeDirectory(at: nested)
        let publicHeader = include.appending(component: "API.h")
        let nestedHeader = nested.appending(component: "API.h")
        let privateHeader = root.appending(component: "Private.hpp")
        try await fileSystem.writeText("#pragma once\n#include \"../Private.hpp\"\n#include \"nested/API.h\"\n", at: publicHeader)
        try await fileSystem.writeText("#pragma once\nint nested_value(void);\n", at: nestedHeader)
        try await fileSystem.writeText("#pragma once\nint private_value(void);\n", at: privateHeader)
        let moduleMap = include.appending(component: "module.modulemap")
        let map: String
        switch kind {
        case .directory:
            map = "module CLib { umbrella \"\(include.pathString)\" export * }"
        case .umbrellaHeader:
            map = "framework module CLib { umbrella header \"\(publicHeader.pathString)\" export * module * { export * } }"
        case .custom:
            map = "// header \"not-a-path\"\nmodule CLib { header \"API.h\" export * }"
        }
        try await fileSystem.writeText(map, at: moduleMap)
        let headers = Headers(
            public: [publicHeader, nestedHeader], private: [], project: [privateHeader],
            sourceLayout: .init(
                root: root, publicHeaders: include, moduleMap: moduleMap,
                moduleName: "CLib", usesDirectoryModuleMap: directoryModule
            )
        )
        let artifact = temporary.appending(component: framework ? "CLib.framework" : "libCLib.a")
        if framework { try await fileSystem.makeDirectory(at: artifact) }
        let version = artifact.appending(components: "Versions", "A")
        if artifactKind == .versionedFramework {
            try await fileSystem.makeDirectory(at: version)
            try await fileSystem.createSymbolicLink(
                from: artifact.appending(components: "Versions", "Current"), to: try RelativePath(validating: "A")
            )
            for name in ["Headers", "Modules", "CLib", "Resources"] {
                try await fileSystem.createSymbolicLink(
                    from: artifact.appending(component: name), to: try RelativePath(validating: "Versions/Current/\(name)")
                )
            }
        }
        let target = Target.test(name: "CLib", product: framework ? .staticFramework : .staticLibrary, headers: headers)
        let exported = try #require(try await SwiftPackageHeadersExporter().export(
            target: target, artifact: artifact
        ))
        // Re-exporting must replace the alias before removing its old destination.
        _ = try await SwiftPackageHeadersExporter().export(
            target: target, artifact: artifact
        )
        let implementation = temporary.appending(component: "implementation.c")
        let object = temporary.appending(component: "implementation.o")
        try await fileSystem.writeText("int value(void) { return 1; }", at: implementation)
        try run(["clang", "-c", implementation.pathString, "-o", object.pathString])
        let binary = framework ? (artifactKind == .versionedFramework ? version : artifact)
            .appending(component: "CLib") : artifact
        try run(["libtool", "-static", "-o", binary.pathString, object.pathString])
        if framework {
            let info = ["CFBundleExecutable": "CLib", "CFBundleIdentifier": "dev.tuist.CLib", "CFBundlePackageType": "FMWK"]
            let resources = artifactKind == .versionedFramework ? version.appending(component: "Resources") : artifact
            try await fileSystem.makeDirectory(at: resources)
            try PropertyListEncoder().encode(info).write(to: resources.appending(component: "Info.plist").url)
        }
        let xcframework = temporary.appending(component: "CLib.xcframework")
        try run(["xcodebuild", "-create-xcframework"] + (
            framework ? ["-framework", artifact.pathString] : ["-library", artifact.pathString, "-headers", exported.pathString]
        ) + ["-output", xcframework.pathString])
        let info = try await PropertyListDecoder().decode(
            XCFrameworkInfoPlist.self, from: fileSystem.readFile(at: xcframework.appending(component: "Info.plist"))
        )
        let library = try #require(info.libraries.first)
        let slice = xcframework.appending(component: library.identifier)
        let directory = framework ? slice.appending(library.path) : slice.appending(try #require(library.headersPath))
        try await fileSystem.remove(root)
        try await fileSystem.remove(artifact)
        if !framework { try await fileSystem.remove(exported) }
        let metadata: SwiftPackageHeadersExporter.Metadata = try await fileSystem.readJSONFile(
            at: (framework ? directory : directory.appending(component: "CLib"))
                .appending(component: SwiftPackageHeadersExporter.Metadata.fileName)
        )
        let publicDirectory = directory.appending(try RelativePath(validating: metadata.publicDirectory))
        let consumer = temporary.appending(component: "consumer.m")
        try await fileSystem.writeText(
            """
            #if __has_include(<CLib/API.h>) != \(directoryModule ? 1 : 0)
            #error Cache export changed module header visibility
            #endif
            @import CLib;
            #include <API.h>
            int use(void) { return private_value() + nested_value(); }
            """,
            at: consumer
        )
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "clang", "-fmodules", "-fsyntax-only", "-Werror", "-x", "objective-c",
            "-fmodules-cache-path=\(temporary.appending(component: "module-cache").pathString)",
            "-I\(publicDirectory.pathString)", consumer.pathString,
        ] + (framework ? ["-F\(slice.pathString)"] : ["-I\(directory.pathString)"])
        if let namespaceDirectory = metadata.namespaceDirectory {
            process.arguments?.append("-I\(directory.appending(try RelativePath(validating: namespaceDirectory)).pathString)")
        }
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(try await fileSystem.exists(publicDirectory.parentDirectory.appending(component: "Private.hpp")))
        #expect(try await fileSystem.exists(publicDirectory.appending(components: "nested", "API.h")))
    }

    private func run(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        try #require(process.terminationStatus == 0, "Command failed: \(arguments)")
    }

    @Test func preservesCustomModuleComposition() throws {
        let layout = Headers.SourceLayout(
            root: "/package/target", publicHeaders: "/package/target/include",
            moduleMap: "/package/target/include/module.modulemap", moduleName: "CLib", usesDirectoryModuleMap: false
        )
        let source = """
        // header "This is a comment"
        module CLib [system] {
            umbrella header "API.h"
            textual header "../Templates.ipp"
            explicit module Detail { private header "detail/Private.h" export * }
            requires cplusplus
            link "c++"
        }
        """
        let result = try SwiftPackageModuleMapRelocator.relocate(source, layout: layout, framework: true)
        #expect(result.contents.contains("framework module CLib [system]"))
        #expect(result.contents.contains("umbrella header \"../TuistHeaders/include/API.h\""))
        #expect(result.contents.contains("textual header \"../TuistHeaders/Templates.ipp\""))
        #expect(result.contents
            .contains("explicit module Detail { private header \"../TuistHeaders/include/detail/Private.h\" export * }"))
        #expect(result.contents.contains("// header \"This is a comment\""))
        #expect(result.contents.contains("requires cplusplus"))
        #expect(result.contents.contains("link \"c++\""))
        #expect(result.references.count == 3)
    }

    @Test func rejectsModuleMapReferencesOutsideTarget() throws {
        let layout = Headers.SourceLayout(
            root: "/package/target", publicHeaders: "/package/target/include",
            moduleMap: "/package/target/include/module.modulemap", moduleName: "CLib",
            usesDirectoryModuleMap: false
        )
        #expect(throws: SwiftPackageHeadersExportError.self) {
            try SwiftPackageModuleMapRelocator.relocate(
                "module CLib { header \"../../Other.h\" export * }", layout: layout, framework: true
            )
        }
    }
}

struct SwiftPackageCachedHeadersMapperTests {
    @Test(.inTemporaryDirectory, arguments: [false, true], [false, true])
    func restoresOnlyMatchingSDKIncludePaths(framework: Bool, directlyLinked: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let artifact = root.appending(component: "CLib.xcframework")
        let headersDirectory = framework ? "CLib.framework" : "Headers"
        for sdk in ["ios-arm64", "macos-arm64"] {
            let directory = artifact.appending(components: sdk, headersDirectory)
            let metadataDirectory = framework ? directory : directory.appending(component: "CLib")
            try await fileSystem.makeDirectory(at: metadataDirectory)
            try await fileSystem.writeAsJSON(
                SwiftPackageHeadersExporter
                    .Metadata(publicDirectory: framework ? "TuistHeaders/include" : "CLib/TuistHeaders/include"),
                at: metadataDirectory.appending(component: SwiftPackageHeadersExporter.Metadata.fileName)
            )
        }
        let libraryPath = try RelativePath(validating: framework ? "CLib.framework" : "libCLib.a")
        let headersPath = framework ? nil : try RelativePath(validating: "Headers")
        let dependency = GraphDependency.testXCFramework(path: artifact, infoPlist: .test(libraries: [
            .test(identifier: "ios-arm64", path: libraryPath, headersPath: headersPath, platform: .iOS),
            .test(identifier: "macos-arm64", path: libraryPath, headersPath: headersPath, platform: .macOS),
        ]))
        let consumer = GraphDependency.target(name: "Consumer", path: root)
        let wrapper = GraphDependency.testXCFramework(path: root.appending(component: "Wrapper.xcframework"))
        let graph = Graph.test(
            path: root, projects: [root: .test(path: root, targets: [.test(name: "Consumer")])],
            dependencies: directlyLinked ? [consumer: [dependency]] : [consumer: [wrapper], wrapper: [dependency]],
            dependencyConditions: [GraphEdge(
                from: directlyLinked ? consumer : wrapper,
                to: dependency
            ): try #require(.when([.ios]))]
        )
        let (mapped, effects, _) = try await SwiftPackageCachedHeadersMapper().map(graph: graph, environment: MapperEnvironment())
        let settings = try #require(mapped.projects[root]?.targets["Consumer"]?.settings?.base)
        let relative = framework ? "TuistHeaders/include" : "CLib/TuistHeaders/include"
        let expected = directlyLinked
            ? "$(BUILT_PRODUCTS_DIR)/\(framework ? "CLib.framework" : "include")/\(relative)"
            : "$(SRCROOT)/CLib.xcframework/ios-arm64/\(headersDirectory)/\(relative)"
        #expect(settings["HEADER_SEARCH_PATHS[sdk=iphoneos*]"] == .array([
            "$(inherited)", "\"\(expected)\"",
        ]))
        #expect(settings["HEADER_SEARCH_PATHS[sdk=macosx*]"] == nil)
        #expect(effects.isEmpty)
    }
}

struct SwiftPackageProcessedHeadersTests {
    @Test(.inTemporaryDirectory, arguments: [false, true])
    func multipleLibrariesShareProductsWithoutCollisionsOrRedefinitions(directoryModule: Bool) async throws {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        let products = root.appending(component: "Products")
        let processedHeaders = products.appending(component: "include")
        try await fileSystem.makeDirectory(at: processedHeaders)
        var dependencies: Set<GraphDependency> = []
        var sourceDirectories: [AbsolutePath] = []
        var artifacts: [AbsolutePath] = []
        for name in ["First", "Second"] {
            let source = root.appending(component: name)
            let include = source.appending(component: "include")
            try await fileSystem.makeDirectory(at: include)
            let header = include.appending(component: "API.h")
            try await fileSystem.writeText("#pragma once\nstruct \(name)Value { int value; };\n", at: header)
            let moduleMap = include.appending(component: "module.modulemap")
            let declaration = directoryModule ? "umbrella \"\(include.pathString)\"" : "header \"API.h\""
            try await fileSystem.writeText("module \(name) { \(declaration) export * }", at: moduleMap)
            let target = Target.test(name: name, product: .staticLibrary, headers: .init(
                public: [header], private: [], project: [], sourceLayout: .init(
                    root: source, publicHeaders: include, moduleMap: moduleMap, moduleName: name,
                    usesDirectoryModuleMap: directoryModule
                )
            ))
            let artifact = root.appending(component: "\(name).xcframework")
            let slice = artifact.appending(component: "macos-arm64")
            let exported = try #require(try await SwiftPackageHeadersExporter().export(
                target: target, artifact: slice.appending(component: "lib\(name).a")
            ))
            // ProcessXCFramework merges each library's Headers root into BUILT_PRODUCTS_DIR/include.
            // Each export must own one distinct namespace, including its map and private tree.
            let entries = try await fileSystem.contentsOfDirectory(exported)
            #expect(entries.map(\.basename) == [name])
            for entry in entries {
                try await fileSystem.copy(entry, to: processedHeaders.appending(component: entry.basename))
            }
            dependencies.insert(.testXCFramework(
                path: artifact,
                infoPlist: .test(libraries: [.test(
                    identifier: "macos-arm64", path: try RelativePath(validating: "lib\(name).a"),
                    headersPath: exported.relative(to: slice), platform: .macOS, architectures: [.arm64]
                )]),
                linking: .static,
                moduleMaps: [exported.appending(components: name, "module.modulemap")]
            ))
            sourceDirectories.append(source)
            artifacts.append(artifact)
        }
        let origin = GraphDependency.target(name: "Consumer", path: root)
        let graph = Graph.test(
            path: root, projects: [root: .test(path: root, targets: [.test(name: "Consumer", platform: .macOS)])],
            dependencies: [origin: dependencies]
        )
        let (mapped, _, _) = try await SwiftPackageCachedHeadersMapper().map(graph: graph, environment: MapperEnvironment())
        let settings = try #require(mapped.projects[root]?.targets["Consumer"]?.settings?.base)
        guard case let .array(searchPaths) = settings["HEADER_SEARCH_PATHS[sdk=macosx*]"] else {
            Issue.record("Missing processed header search paths")
            return
        }
        for path in sourceDirectories + artifacts {
            try await fileSystem.remove(path)
        }
        let consumer = root.appending(component: "Consumer.m")
        try await fileSystem.writeText("""
        @import First;
        @import Second;
        #include <API.h>
        #if \(directoryModule ? 1 : 0)
        #include <First/API.h>
        #include <Second/API.h>
        #elif __has_include(<First/API.h>) || __has_include(<Second/API.h>)
        #error Custom modules gained a framework namespace
        #endif
        struct FirstValue first;
        struct SecondValue second;
        """, at: consumer)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = [
            "clang", "-fmodules", "-fsyntax-only", "-Werror", "-x", "objective-c",
            "-fmodules-cache-path=\(root.appending(component: "module-cache").pathString)",
            "-I\(processedHeaders.pathString)", consumer.pathString,
        ] + searchPaths.filter { $0 != "$(inherited)" }.map {
            "-I" + $0.replacingOccurrences(of: "$(BUILT_PRODUCTS_DIR)", with: products.pathString)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}
