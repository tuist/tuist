import FileSystem
import Mockable
import Path
import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct PBXProjectMapperTests: Sendable {
    private let fileSystem = FileSystem()

    @Test("Maps a basic project with default attributes")
    func mapBasicProject() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let mapper = PBXProjectMapper()

        // When
        let project = try await mapper.map(xcodeProj: xcodeProj, projectNativeTargets: [:])

        // Then
        #expect(project.name == "TestProject")
        #expect(project.path == xcodeProj.srcPath)
        #expect(project.sourceRootPath == xcodeProj.srcPath)
        #expect(project.xcodeProjPath == xcodeProj.projectPath)
        #expect(project.type == .local)
    }

    @Test("Maps a project with custom attributes (org name, class prefix, upgrade check)")
    func mapProjectWithCustomAttributes() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()

        let mapper = PBXProjectMapper()

        let customAttributes: [String: ProjectAttribute] = [
            "ORGANIZATIONNAME": "Example Org",
            "CLASSPREFIX": "EX",
            "LastUpgradeCheck": "1500",
        ]
        xcodeProj.pbxproj.projects.first?.attributes = customAttributes

        // When
        let project = try await mapper.map(xcodeProj: xcodeProj, projectNativeTargets: [:])

        // Then
        #expect(project.name == "TestProject")
        #expect(project.organizationName == "Example Org")
        #expect(project.classPrefix == "EX")
        #expect(project.lastUpgradeCheck == "1500")
    }

    @Test("Maps a project with local packages")
    func mapProjectWithLocalPackages() async throws {
        try await fileSystem.runInTemporaryDirectory(prefix: "PBXProjectMapperTests") { path in
            // Given
            let xcodeProj = try await XcodeProj.test(
                path: path.appending(component: "App.xcodeproj")
            )
            let pbxProj = xcodeProj.pbxproj

            let appGroup = try PBXFileSystemSynchronizedRootGroup(
                path: "App",
                exceptions: []
            )
            .addToMainGroup(in: xcodeProj.pbxproj)
            let fileReference = PBXFileReference(
                sourceTree: .group,
                path: "LibraryB"
            )
            let packagesGroup = try PBXGroup(
                children: [
                    fileReference,
                ],
                sourceTree: .sourceRoot,
                path: "Group"
            )
            .addToMainGroup(in: pbxProj)
            // We need to keep these references, so they are not deinitialized
            _ = appGroup
            _ = packagesGroup
            let target = try PBXNativeTarget(name: "App")
                .add(to: pbxProj)
                .add(to: pbxProj.rootObject)

            let libraryAPath = path.appending(components: "App", "LibraryA")
            try await fileSystem.makeDirectory(at: libraryAPath)
            try await fileSystem.touch(libraryAPath.appending(component: "Package.swift"))

            let libraryBPath = path.appending(components: "Group", "LibraryB")
            try await fileSystem.makeDirectory(at: libraryBPath)
            try await fileSystem.touch(libraryBPath.appending(component: "Package.swift"))
            let targetMapper = MockPBXTargetMapping()
            given(targetMapper)
                .map(
                    pbxTarget: .any,
                    xcodeProj: .any,
                    projectNativeTargets: .any,
                    packages: .any
                )
                .willReturn(.test())

            let mapper = PBXProjectMapper(targetMapper: targetMapper)

            // When
            let project = try await mapper.map(
                xcodeProj: xcodeProj,
                projectNativeTargets: [:]
            )

            // Then
            try #expect(
                project.packages.map(\.url).map { try AbsolutePath(validating: $0) }.map(\.basename).sorted() == [
                    libraryAPath.basename,
                    libraryBPath.basename,
                ]
            )
            verify(targetMapper)
                .map(
                    pbxTarget: .value(target),
                    xcodeProj: .value(xcodeProj),
                    projectNativeTargets: .any,
                    packages: .matching { $0.count == 2 }
                )
                .called(1)
        }
    }

    @Test("Maps a project with remote package dependencies")
    func mapProjectWithRemotePackages() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let package = XCRemoteSwiftPackageReference(
            repositoryURL: "https://github.com/example/package.git",
            versionRequirement: .upToNextMajorVersion("1.0.0")
        )
        pbxProj.add(object: package)
        try xcodeProj.mainPBXProject().remotePackages.append(package)
        let mapper = PBXProjectMapper()

        // When
        let project = try await mapper.map(xcodeProj: xcodeProj, projectNativeTargets: [:])

        // Then
        #expect(project.packages.count == 1)
        guard case let .remote(url, requirement) = project.packages[0] else {
            Issue.record("Expected remote package")
            return
        }
        #expect(url == "https://github.com/example/package.git")
        #expect(requirement == .upToNextMajor("1.0.0"))
    }

    @Test("Maps a project with known regions")
    func mapProjectWithKnownRegions() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        try xcodeProj.mainPBXProject().knownRegions = ["en", "es", "fr"]
        let mapper = PBXProjectMapper()

        // When
        let project = try await mapper.map(xcodeProj: xcodeProj, projectNativeTargets: [:])

        // Then
        #expect(project.defaultKnownRegions?.count == 3)
        #expect(project.defaultKnownRegions?.contains("en") == true)
        #expect(project.defaultKnownRegions?.contains("es") == true)
        #expect(project.defaultKnownRegions?.contains("fr") == true)
    }

    @Test("Maps a project with a custom development region")
    func mapProjectWithDevelopmentRegion() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        try xcodeProj.mainPBXProject().developmentRegion = "fr"
        let mapper = PBXProjectMapper()

        // When
        let project = try await mapper.map(xcodeProj: xcodeProj, projectNativeTargets: [:])

        // Then
        #expect(project.developmentRegion == "fr")
    }

    @Test("Maps a project with default resource synthesizers")
    func mapProjectWithResourceSynthesizers() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let mapper = PBXProjectMapper()

        // When
        let project = try await mapper.map(xcodeProj: xcodeProj, projectNativeTargets: [:])
        let synthesizers = project.resourceSynthesizers

        // Then
        // Check for strings synthesizer
        let stringsSynthesizer = synthesizers.first { $0.parser == .strings }
        #expect(stringsSynthesizer != nil)
        #expect(stringsSynthesizer?.extensions.contains("strings") == true)
        #expect(stringsSynthesizer?.extensions.contains("stringsdict") == true)

        // Check for assets synthesizer
        let assetsSynthesizer = synthesizers.first { $0.parser == .assets }
        #expect(assetsSynthesizer != nil)
        #expect(assetsSynthesizer?.extensions.contains("xcassets") == true)

        // Verify all expected synthesizer types are present
        let expectedParsers: Set<ResourceSynthesizer.Parser> = [
            .strings, .assets, .plists, .fonts, .coreData,
            .interfaceBuilder, .json, .yaml, .files, .stringsCatalog,
        ]
        let actualParsers = Set(synthesizers.map(\.parser))
        #expect(actualParsers == expectedParsers)
    }

    @Test("Maps a project with associated schemes")
    func mapProjectWithSchemes() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let scheme = XCScheme.test(name: "TestScheme")
        xcodeProj.sharedData = XCSharedData(schemes: [scheme])
        let mapper = PBXProjectMapper()

        // When
        let project = try await mapper.map(xcodeProj: xcodeProj, projectNativeTargets: [:])

        // Then
        #expect(project.schemes.count == 1)
        #expect(project.schemes[0].name == "TestScheme")
    }
}
