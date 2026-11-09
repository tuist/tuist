import FileSystem
import FileSystemTesting
import Foundation
import Path
import TestCoverageAttribution
import Testing
import TuistTesting
import XcodeGraph
import XcodeGraphMapper
@testable import TuistCore

@Suite(.coverageAttribution)
struct TestImpactAffectedModulesTests {
    /// A plain Xcode project with file references, mapped as a project without manifests is: a
    /// framework with a source and an asset catalog, its unit tests, an unrelated framework, and a
    /// project-level `.xcconfig`.
    @Test(.inTemporaryDirectory) func mapsAPlainXcodeProjectsFileReferencesToTheirTestModules() async throws {
        let repository = try #require(FileSystem.temporaryTestDirectory)
        let fileSystem = FileSystem()
        for file in [
            "Feature/Feature.swift",
            "Feature/Assets.xcassets/Contents.json",
            "FeatureTests/FeatureTests.swift",
            "Other/Other.swift",
            "Base.xcconfig",
        ] {
            let path = try repository.appending(RelativePath(validating: file))
            try await fileSystem.makeDirectory(at: path.parentDirectory)
            try await fileSystem.writeText("", at: path)
        }
        let xcodeProjPath = repository.appending(component: "Feature.xcodeproj")
        try await fileSystem.makeDirectory(at: xcodeProjPath)
        try await fileSystem.writeText(Self.pbxproj, at: xcodeProjPath.appending(component: "project.pbxproj"))

        let subject = TestImpactAffectedModules(graph: try await XcodeGraphMapper().map(at: xcodeProjPath))
        // The temporary directory is under `/private/var`, as Git reports it, while the mapper drops
        // `/private` from the file references.
        #expect(subject.affectedModules(path: repository.appending(components: "Feature", "Feature.swift")) == ["FeatureTests"])
        #expect(subject.affectedModules(
            path: repository.appending(components: "Feature", "Assets.xcassets", "Contents.json")
        ) == ["FeatureTests"])
        #expect(subject.affectedModules(
            path: repository.appending(components: "FeatureTests", "FeatureTests.swift")
        ) == ["FeatureTests"])
        #expect(subject.affectedModules(path: repository.appending(components: "Other", "Other.swift")) == [])
        #expect(subject.affectedModules(path: repository.appending(component: "README.md")) == [])
        #expect(subject.affectedModules(path: repository.appending(component: "Base.xcconfig")) == nil)
        #expect(subject.affectedModules(path: xcodeProjPath.appending(component: "project.pbxproj")) == nil)
    }

    private static let pbxproj = """
    // !$*UTF8*$!
    {
    archiveVersion = 1;
    classes = {
    };
    objectVersion = 56;
    objects = {
    000000000000000000000020 = {isa = PBXBuildFile; fileRef = 000000000000000000000010; };
    000000000000000000000021 = {isa = PBXBuildFile; fileRef = 000000000000000000000011; };
    000000000000000000000022 = {isa = PBXBuildFile; fileRef = 000000000000000000000012; };
    000000000000000000000023 = {isa = PBXBuildFile; fileRef = 000000000000000000000013; };
    000000000000000000000050 = {isa = PBXContainerItemProxy; containerPortal = 000000000000000000000001; \
    proxyType = 1; remoteGlobalIDString = 000000000000000000000040; remoteInfo = Feature; };
    000000000000000000000010 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Feature.swift; \
    sourceTree = "<group>"; };
    000000000000000000000011 = {isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; \
    path = Assets.xcassets; sourceTree = "<group>"; };
    000000000000000000000012 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; \
    path = FeatureTests.swift; sourceTree = "<group>"; };
    000000000000000000000013 = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Other.swift; \
    sourceTree = "<group>"; };
    000000000000000000000014 = {isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Base.xcconfig; \
    sourceTree = "<group>"; };
    000000000000000000000015 = {isa = PBXFileReference; explicitFileType = wrapper.framework; \
    includeInIndex = 0; path = Feature.framework; sourceTree = BUILT_PRODUCTS_DIR; };
    000000000000000000000016 = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; \
    includeInIndex = 0; path = FeatureTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
    000000000000000000000017 = {isa = PBXFileReference; explicitFileType = wrapper.framework; \
    includeInIndex = 0; path = Other.framework; sourceTree = BUILT_PRODUCTS_DIR; };
    000000000000000000000002 = {isa = PBXGroup; children = (000000000000000000000014, 000000000000000000000004, \
    000000000000000000000005, 000000000000000000000006, 000000000000000000000003, ); sourceTree = "<group>"; };
    000000000000000000000003 = {isa = PBXGroup; children = (000000000000000000000015, 000000000000000000000016, \
    000000000000000000000017, ); name = Products; sourceTree = "<group>"; };
    000000000000000000000004 = {isa = PBXGroup; children = (000000000000000000000010, 000000000000000000000011, ); \
    path = Feature; sourceTree = "<group>"; };
    000000000000000000000005 = {isa = PBXGroup; children = (000000000000000000000012, ); path = FeatureTests; \
    sourceTree = "<group>"; };
    000000000000000000000006 = {isa = PBXGroup; children = (000000000000000000000013, ); path = Other; \
    sourceTree = "<group>"; };
    000000000000000000000040 = {isa = PBXNativeTarget; buildConfigurationList = 000000000000000000000061; \
    buildPhases = (000000000000000000000030, 000000000000000000000031, ); buildRules = ( ); dependencies = ( ); \
    name = Feature; productName = Feature; productReference = 000000000000000000000015; \
    productType = "com.apple.product-type.framework"; };
    000000000000000000000041 = {isa = PBXNativeTarget; buildConfigurationList = 000000000000000000000062; \
    buildPhases = (000000000000000000000032, ); buildRules = ( ); dependencies = (000000000000000000000051, ); \
    name = FeatureTests; productName = FeatureTests; productReference = 000000000000000000000016; \
    productType = "com.apple.product-type.bundle.unit-test"; };
    000000000000000000000042 = {isa = PBXNativeTarget; buildConfigurationList = 000000000000000000000063; \
    buildPhases = (000000000000000000000033, ); buildRules = ( ); dependencies = ( ); name = Other; \
    productName = Other; productReference = 000000000000000000000017; \
    productType = "com.apple.product-type.framework"; };
    000000000000000000000001 = {isa = PBXProject; buildConfigurationList = 000000000000000000000060; \
    compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, ); \
    mainGroup = 000000000000000000000002; productRefGroup = 000000000000000000000003; projectDirPath = ""; \
    projectRoot = ""; targets = (000000000000000000000040, 000000000000000000000041, 000000000000000000000042, ); };
    000000000000000000000031 = {isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; \
    files = (000000000000000000000021, ); runOnlyForDeploymentPostprocessing = 0; };
    000000000000000000000030 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; \
    files = (000000000000000000000020, ); runOnlyForDeploymentPostprocessing = 0; };
    000000000000000000000032 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; \
    files = (000000000000000000000022, ); runOnlyForDeploymentPostprocessing = 0; };
    000000000000000000000033 = {isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; \
    files = (000000000000000000000023, ); runOnlyForDeploymentPostprocessing = 0; };
    000000000000000000000051 = {isa = PBXTargetDependency; target = 000000000000000000000040; \
    targetProxy = 000000000000000000000050; };
    000000000000000000000070 = {isa = XCBuildConfiguration; baseConfigurationReference = 000000000000000000000014; \
    buildSettings = { SDKROOT = iphoneos; }; name = Debug; };
    000000000000000000000071 = {isa = XCBuildConfiguration; buildSettings = { PRODUCT_NAME = Feature; }; \
    name = Debug; };
    000000000000000000000072 = {isa = XCBuildConfiguration; buildSettings = { PRODUCT_NAME = FeatureTests; }; \
    name = Debug; };
    000000000000000000000073 = {isa = XCBuildConfiguration; buildSettings = { PRODUCT_NAME = Other; }; \
    name = Debug; };
    000000000000000000000060 = {isa = XCConfigurationList; buildConfigurations = (000000000000000000000070, ); \
    defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
    000000000000000000000061 = {isa = XCConfigurationList; buildConfigurations = (000000000000000000000071, ); \
    defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
    000000000000000000000062 = {isa = XCConfigurationList; buildConfigurations = (000000000000000000000072, ); \
    defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
    000000000000000000000063 = {isa = XCConfigurationList; buildConfigurations = (000000000000000000000073, ); \
    defaultConfigurationIsVisible = 0; defaultConfigurationName = Debug; };
    };
    rootObject = 000000000000000000000001;
    }
    """

    @Test func comparesPathsWithoutMacOSsPrivatePrefix() throws {
        func subject(projectAt projectPath: AbsolutePath) -> TestImpactAffectedModules {
            let featureTests = Target.test(
                name: "FeatureTests",
                product: .unitTests,
                settings: nil,
                sources: [SourceFile(path: projectPath.appending(components: "FeatureTests", "FeatureTests.swift"))]
            )
            let project = Project.test(
                path: projectPath,
                xcodeProjPath: projectPath.appending(component: "Feature.xcodeproj"),
                settings: .test(configurations: [:]),
                targets: [featureTests]
            )
            return TestImpactAffectedModules(graph: Graph.test(projects: [projectPath: project]))
        }
        let resolved = try AbsolutePath(validating: "/private/var/repo")
        let unresolved = try AbsolutePath(validating: "/var/repo")

        // A graph keyed one way answers paths given the other way, deleted files included, since
        // the file system isn't consulted.
        #expect(subject(projectAt: unresolved).affectedModules(
            path: resolved.appending(components: "FeatureTests", "FeatureTests.swift")
        ) == ["FeatureTests"])
        #expect(subject(projectAt: resolved).affectedModules(
            path: unresolved.appending(components: "FeatureTests", "FeatureTests.swift")
        ) == ["FeatureTests"])
        #expect(subject(projectAt: unresolved).affectedModules(
            path: resolved.appending(components: "Feature.xcodeproj", "project.pbxproj")
        ) == nil)
        // Only the system's `/private` directories map: another `/private` path is left alone.
        #expect(subject(projectAt: try AbsolutePath(validating: "/repo")).affectedModules(
            path: try AbsolutePath(validating: "/private/repo/FeatureTests/FeatureTests.swift")
        ) == [])
    }

    @Test func attributesFilesInsideABuildableFolderExceptTheExcludedOnes() throws {
        let projectPath = try AbsolutePath(validating: "/Repo")
        let feature = Target.test(
            name: "Feature",
            product: .framework,
            settings: nil,
            buildableFolders: [
                BuildableFolder(
                    path: projectPath.appending(component: "Feature"),
                    exceptions: BuildableFolderExceptions(exceptions: [
                        BuildableFolderException(
                            excluded: [projectPath.appending(components: "Feature", "Scripts")],
                            compilerFlags: [:],
                            publicHeaders: [],
                            privateHeaders: []
                        ),
                    ]),
                    resolvedFiles: []
                ),
            ]
        )
        let featureTests = Target.test(
            name: "FeatureTests",
            product: .unitTests,
            settings: nil,
            sources: [SourceFile(path: projectPath.appending(components: "FeatureTests", "FeatureTests.swift"))]
        )
        let project = Project.test(
            path: projectPath,
            xcodeProjPath: projectPath.appending(component: "Feature.xcodeproj"),
            settings: .test(configurations: [.debug: .test(xcconfig: projectPath.appending(component: "Base.xcconfig"))]),
            targets: [feature, featureTests]
        )
        let graph = Graph.test(
            projects: [projectPath: project],
            dependencies: [
                .target(name: "FeatureTests", path: projectPath): [.target(name: "Feature", path: projectPath)],
            ]
        )
        let subject = TestImpactAffectedModules(graph: graph)

        // A file the folder doesn't list yet, such as a deleted one, still belongs to it.
        #expect(subject.affectedModules(path: projectPath.appending(components: "Feature", "Deleted.swift")) == ["FeatureTests"])
        #expect(subject.affectedModules(path: projectPath.appending(components: "Feature", "Scripts", "lint.sh")) == [])
        #expect(subject.affectedModules(
            path: projectPath.appending(components: "FeatureTests", "FeatureTests.swift")
        ) == ["FeatureTests"])
        #expect(subject.affectedModules(path: projectPath.appending(component: "Base.xcconfig")) == nil)
        #expect(subject.affectedModules(
            path: projectPath.appending(components: "Feature.xcodeproj", "project.pbxproj")
        ) == nil)
    }
}
