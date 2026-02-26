import FileSystem
import Foundation
import Path
import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct PBXTargetMapperTests: Sendable {
    private let fileSystem = FileSystem()

    @Test("Maps a basic target with a product bundle identifier")
    func mapBasicTarget() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let target = createTarget(
            name: "App",
            xcodeProj: xcodeProj,
            productType: .application,
            buildSettings: ["PRODUCT_BUNDLE_IDENTIFIER": "com.example.app"]
        )
        try xcodeProj.mainPBXProject().targets.append(target)
        try xcodeProj.write(path: try #require(xcodeProj.path))

        // When
        let mapper = PBXTargetMapper()

        let mapped = try #require(
            try await mapper.map(
                pbxTarget: target,
                xcodeProj: xcodeProj,
                projectNativeTargets: [:],
                packages: []
            )
        )

        // Then
        #expect(mapped.name == "App")
        #expect(mapped.product == .app)
        #expect(mapped.productName == "App")
        #expect(mapped.bundleId == "com.example.app")
    }

    @Test("Defaults to unknown if the target is missing a bundle identifier")
    func mapTargetWithMissingBundleId() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let target = createTarget(
            name: "App",
            xcodeProj: xcodeProj,
            productType: .application,
            buildSettings: [:]
        )
        let mapper = PBXTargetMapper()

        // When
        let mapped = try #require(
            try await mapper.map(
                pbxTarget: target,
                xcodeProj: xcodeProj,
                projectNativeTargets: [:],
                packages: []
            )
        )

        // Then
        #expect(mapped.bundleId == "Unknown")
    }

    @Test("Maps a target with source files")
    func mapTargetWithSourceFiles() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let pbxProj = xcodeProj.pbxproj
        let sourceFile = try PBXFileReference.test(
            path: "ViewController.swift",
            lastKnownFileType: "sourcecode.swift"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)

        let buildFile = PBXBuildFile(file: sourceFile).add(to: pbxProj)
        let sourcesPhase = PBXSourcesBuildPhase(files: [buildFile]).add(to: pbxProj)

        let target = createTarget(
            name: "App",
            xcodeProj: xcodeProj,
            productType: .application,
            buildPhases: [sourcesPhase],
            buildSettings: ["PRODUCT_BUNDLE_IDENTIFIER": "com.example.app"]
        )
        let mapper = PBXTargetMapper()

        // When
        let mapped = try #require(
            try await mapper.map(
                pbxTarget: target,
                xcodeProj: xcodeProj,
                projectNativeTargets: [:],
                packages: []
            )
        )

        // Then
        #expect(mapped.sources.count == 1)
        #expect(mapped.sources[0].path.basename == "ViewController.swift")
    }

    @Test("Maps a target with a buildable group")
    func mapTargetWithBuildableGroup() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "PBXTargetMapperTests") { appPath in
            // Given
            let xcodeProj = try await XcodeProj.test(
                path: appPath.appending(component: "App.xcodeproj")
            )
            let pbxProj = xcodeProj.pbxproj
            let sourcesPhase = PBXSourcesBuildPhase(files: []).add(to: pbxProj)

            let target = createTarget(
                name: "App",
                xcodeProj: xcodeProj,
                productType: .application,
                buildPhases: [sourcesPhase],
                buildSettings: ["PRODUCT_BUNDLE_IDENTIFIER": "com.example.app"]
            )
            let exceptionSet = PBXFileSystemSynchronizedBuildFileExceptionSet(
                target: target,
                membershipExceptions: [
                    "Ignored.cpp",
                    "Ignored.h",
                ],
                publicHeaders: [
                    "Public.h",
                ],
                privateHeaders: [
                    "Private.hpp",
                ],
                additionalCompilerFlagsByRelativePath: [
                    "File.swift": "compiler-flag",
                ],
                attributesByRelativePath: [
                    "Optional.framework": ["Weak"],
                ]
            )
            let rootGroup = PBXFileSystemSynchronizedRootGroup(
                path: "App",
                exceptions: [
                    exceptionSet,
                ]
            )
            target.fileSystemSynchronizedGroups = [
                rootGroup,
            ]
            let buildableGroupPath = appPath.appending(component: "App")
            try await fileSystem.makeDirectory(at: buildableGroupPath)

            // Sources
            try await fileSystem.touch(buildableGroupPath.appending(component: "File.swift"))
            try await fileSystem.touch(buildableGroupPath.appending(component: "File.cpp"))
            try await fileSystem.touch(buildableGroupPath.appending(component: "Ignored.cpp"))
            try await fileSystem.makeDirectory(at: buildableGroupPath.appending(component: "Nested"))
            try await fileSystem.touch(buildableGroupPath.appending(component: "File.c"))
            try await fileSystem.makeDirectory(at: buildableGroupPath.appending(component: "App.docc"))

            // Resources
            try await fileSystem.makeDirectory(at: buildableGroupPath.appending(component: "Location.geojson"))
            try await fileSystem.makeDirectory(at: buildableGroupPath.appending(component: "App.xcassets"))

            // Headers
            try await fileSystem.touch(buildableGroupPath.appending(component: "Public.h"))
            try await fileSystem.touch(buildableGroupPath.appending(component: "Project.h"))
            try await fileSystem.touch(buildableGroupPath.appending(component: "Ignored.h"))
            try await fileSystem.touch(buildableGroupPath.appending(component: "Private.hpp"))

            // Frameworks
            try await fileSystem.makeDirectory(at: buildableGroupPath.appending(component: "Framework.framework"))
            try await fileSystem.makeDirectory(at: buildableGroupPath.appending(component: "Optional.framework"))

            // Packages
            let packagePath = buildableGroupPath.appending(component: "PackageLibrary")
            try await fileSystem.makeDirectory(at: packagePath)
            try await fileSystem.touch(packagePath.appending(component: "Package.swift"))

            let mapper = PBXTargetMapper(
                fileSystem: fileSystem
            )

            // When
            let mapped = try #require(
                try await mapper.map(
                    pbxTarget: target,
                    xcodeProj: xcodeProj,
                    projectNativeTargets: [:],
                    packages: [
                        packagePath,
                    ]
                )
            )

            // Then
            #expect(
                mapped.sources.sorted(by: { $0.path < $1.path }).map(\.compilerFlags) == [
                    nil,
                    nil,
                    nil,
                    "compiler-flag",
                ]
            )
            #expect(
                mapped.sources.map(\.path.basename).sorted() == [
                    "App.docc",
                    "File.c",
                    "File.cpp",
                    "File.swift",
                ]
            )
            #expect(
                mapped.resources.resources.map(\.path.basename).sorted() == [
                    "App.xcassets",
                    "Location.geojson",
                ]
            )
            #expect(
                mapped.headers?.private.map(\.basename) == [
                    "Private.hpp",
                ]
            )
            #expect(
                mapped.headers?.public.map(\.basename) == [
                    "Public.h",
                ]
            )
            #expect(
                mapped.headers?.project.map(\.basename) == [
                    "Project.h",
                ]
            )
            #expect(
                mapped.dependencies == [
                    .framework(
                        path: buildableGroupPath.appending(component: "Framework.framework"),
                        status: .required,
                        condition: nil
                    ),
                    .framework(
                        path: buildableGroupPath.appending(component: "Optional.framework"),
                        status: .optional,
                        condition: nil
                    ),
                ]
            )
        }
    }

    @Test("Maps entitlements when CODE_SIGN_ENTITLEMENTS is set")
    func mapEntitlements() async throws {
        // Given

        let xcodeProj = try await XcodeProj.test()
        let sourceDirectory = xcodeProj.srcPath
        let entitlementsPath = sourceDirectory.appending(component: "App.entitlements")

        let buildSettings: BuildSettings = [
            "PRODUCT_BUNDLE_IDENTIFIER": "com.example.app",
            "CODE_SIGN_ENTITLEMENTS": "App.entitlements",
        ]

        let debugConfig = XCBuildConfiguration(
            name: "Debug",
            buildSettings: buildSettings
        )

        let configurationList = XCConfigurationList(
            buildConfigurations: [debugConfig],
            defaultConfigurationName: "Debug"
        )

        xcodeProj.pbxproj.add(object: debugConfig)
        xcodeProj.pbxproj.add(object: configurationList)

        let sourceFile = try PBXFileReference.test(
            path: "ViewController.swift",
            lastKnownFileType: "sourcecode.swift"
        ).add(to: xcodeProj.pbxproj).addToMainGroup(in: xcodeProj.pbxproj)

        let buildFile = PBXBuildFile(file: sourceFile).add(to: xcodeProj.pbxproj).add(to: xcodeProj.pbxproj)
        let sourcesPhase = PBXSourcesBuildPhase(files: [buildFile]).add(to: xcodeProj.pbxproj).add(to: xcodeProj.pbxproj)

        // Add targets to each project
        let target = try PBXNativeTarget.test(
            name: "ATarget",
            buildConfigurationList: configurationList,
            buildPhases: [sourcesPhase],
            productType: .framework
        )
        .add(to: xcodeProj.pbxproj)
        .add(to: xcodeProj.pbxproj.rootObject)

        let mapper = PBXTargetMapper()

        // When
        let mapped = try await mapper.map(
            pbxTarget: target,
            xcodeProj: xcodeProj,
            projectNativeTargets: [:],
            packages: []
        )

        // Then
        #expect(mapped?.entitlements == .file(
            path: entitlementsPath,
            configuration: BuildConfiguration(name: "Debug", variant: .debug)
        ))
    }

    @Test("Throws noProjectsFound when pbxProj has no projects")
    func mapTarget_noProjectsFound() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let target = PBXNativeTarget.test()

        try xcodeProj.mainPBXProject().targets.append(target)
        try xcodeProj.write(path: try #require(xcodeProj.path))

        let mapper = PBXTargetMapper()

        // When / Then

        do {
            _ = try await mapper.map(
                pbxTarget: target,
                xcodeProj: xcodeProj,
                projectNativeTargets: [:],
                packages: []
            )
            Issue.record("Should throw an error")
        } catch {
            let err = try #require(error as? PBXObjectError)
            #expect(err.description == "The PBXObjects instance has been released before saving.")
        }
    }

    @Test("Returns a plist path")
    func mapTarget_withPlist() async throws {
        // Given

        let xcodeProj = try await XcodeProj.test()
        let srcPath = xcodeProj.srcPath
        let relativePath = try RelativePath(validating: "Info.plist")
        let plistPath = srcPath.appending(relativePath)

        let plistContent: [String: Any] = [
            "CFBundleIdentifier": "com.example.app",
            "CFBundleName": "ExampleApp",
            "CFVersion": 1.4,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plistContent, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath.pathString))

        let target = createTarget(
            name: "App",
            xcodeProj: xcodeProj,
            productType: .application,
            buildSettings: [
                "PRODUCT_BUNDLE_IDENTIFIER": "com.example.app",
                "INFOPLIST_FILE": .string(relativePath.pathString),
            ]
        )

        try xcodeProj.write(path: try #require(xcodeProj.path))
        let mapper = PBXTargetMapper()

        // When
        let mapped = try await mapper.map(
            pbxTarget: target,
            xcodeProj: xcodeProj,
            projectNativeTargets: [:],
            packages: []
        )

        // Then
        #expect({
            switch mapped?.infoPlist {
            case let .file(path, _):
                return path == plistPath
            default:
                return false
            }
        }() == true)
    }

    @Test
    func mapAggregateTarget() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let target = PBXAggregateTarget(
            name: "App"
        )

        try xcodeProj.write(path: try #require(xcodeProj.path))
        let mapper = PBXTargetMapper()

        // When
        let mapped = try await mapper.map(
            pbxTarget: target,
            xcodeProj: xcodeProj,
            projectNativeTargets: [:],
            packages: []
        )

        // Then
        #expect(mapped == nil)
    }

    // MARK: - Helper Methods

    private func createTarget(
        name: String,
        xcodeProj: XcodeProj,
        productType: PBXProductType,
        buildPhases: [PBXBuildPhase] = [],
        buildSettings: [String: BuildSetting] = [:],
        dependencies: [PBXTargetDependency] = []
    ) -> PBXNativeTarget {
        let debugConfig = XCBuildConfiguration(
            name: "Debug",
            buildSettings: buildSettings
        )

        let releaseConfig = XCBuildConfiguration(
            name: "Release",
            buildSettings: buildSettings
        )

        let configurationList = XCConfigurationList(
            buildConfigurations: [debugConfig, releaseConfig],
            defaultConfigurationName: "Release"
        )

        xcodeProj.pbxproj.add(object: debugConfig)
        xcodeProj.pbxproj.add(object: releaseConfig)
        xcodeProj.pbxproj.add(object: configurationList)

        return PBXNativeTarget.test(
            name: name,
            buildConfigurationList: configurationList,
            buildRules: [],
            buildPhases: buildPhases,
            dependencies: dependencies,
            productType: productType
        )
    }
}
