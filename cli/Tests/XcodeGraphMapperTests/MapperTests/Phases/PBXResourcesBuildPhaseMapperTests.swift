import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct PBXResourcesBuildPhaseMapperTests {
    @Test("Maps resources (like xcassets) from resources phase")
    func mapResources() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let assetRef = try PBXFileReference(
            sourceTree: .group,
            name: "Assets.xcassets",
            path: "Assets.xcassets"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)
        .add(to: pbxProj)

        let buildFile = PBXBuildFile(file: assetRef).add(to: pbxProj)
        let resourcesPhase = PBXResourcesBuildPhase(files: [buildFile]).add(to: pbxProj)

        try PBXNativeTarget(
            name: "App",
            buildPhases: [resourcesPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let mapper = PBXResourcesBuildPhaseMapper()

        // When
        let (resources, _) = try mapper.map(resourcesPhase, xcodeProj: xcodeProj, projectNativeTargets: [:])

        // Then
        #expect(resources.count == 1)
        let resource = try #require(resources.first)
        switch resource {
        case let .file(path, _, _):
            #expect(path.basename == "Assets.xcassets")
        default:
            Issue.record("Expected a file resource.")
        }
    }

    @Test("Maps resource bundle target dependencies from resources phase")
    func mapResourceBundleTargets() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let targetABundle = try PBXFileReference(
            sourceTree: .buildProductsDir,
            path: "TargetA.bundle"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)
        .add(to: pbxProj)

        let buildFile = PBXBuildFile(file: targetABundle).add(to: pbxProj)

        let projectTargetPath = xcodeProj.projectPath.parentDirectory.appending(
            components: "AnotherProject",
            "AnotherProject.xcodeproj"
        )
        let targetBFrameworkRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            path: "TargetB.bundle"
        )
        let targetBFrameworkBuildFile = PBXBuildFile(file: targetBFrameworkRef).add(to: pbxProj)

        let resourcesPhase = PBXResourcesBuildPhase(files: [buildFile, targetBFrameworkBuildFile]).add(to: pbxProj)

        try PBXNativeTarget(
            name: "App",
            buildPhases: [resourcesPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        PBXNativeTarget(
            name: "TargetA",
            buildPhases: [resourcesPhase],
            productType: .bundle
        )
        .add(to: pbxProj)

        let mapper = PBXResourcesBuildPhaseMapper()

        // When
        let (_, resourceDependencies) = try await mapper.map(
            resourcesPhase,
            xcodeProj: xcodeProj,
            projectNativeTargets: [
                "TargetB": ProjectNativeTarget(
                    nativeTarget: .test(
                        name: "TargetB"
                    ),
                    project: .test(
                        path: projectTargetPath
                    )
                ),
            ]
        )

        // Then
        #expect(
            resourceDependencies == [
                .target(
                    name: "TargetA",
                    status: .required,
                    condition: nil
                ),
                .project(
                    target: "TargetB",
                    path: projectTargetPath.parentDirectory,
                    status: .required,
                    condition: nil
                ),
            ]
        )
    }

    @Test("Maps localized variant groups from resources")
    func mapVariantGroup() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let fileRef1 = PBXFileReference.test(
            name: "Localizable.strings",
            path: "en.lproj/Localizable.strings"
        ).add(to: pbxProj)
        let fileRef2 = PBXFileReference.test(
            name: "Localizable.strings",
            path: "fr.lproj/Localizable.strings"
        ).add(to: pbxProj)

        let variantGroup = try PBXVariantGroup.mockVariant(
            children: [fileRef1, fileRef2]
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)

        let buildFile = PBXBuildFile(file: variantGroup).add(to: pbxProj)
        let resourcesPhase = PBXResourcesBuildPhase(files: [buildFile]).add(to: pbxProj)

        try PBXNativeTarget.test(buildPhases: [resourcesPhase])
            .add(to: pbxProj)
            .add(to: pbxProj.rootObject)

        let mapper = PBXResourcesBuildPhaseMapper()

        // When
        let (resources, _) = try mapper.map(resourcesPhase, xcodeProj: xcodeProj, projectNativeTargets: [:])

        // Then
        #expect(resources.count == 2)
        #expect(resources.first?.path.basename == "Localizable.strings")
    }
}
