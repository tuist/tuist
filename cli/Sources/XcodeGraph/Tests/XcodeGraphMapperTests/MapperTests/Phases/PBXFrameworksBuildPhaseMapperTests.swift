import Path
import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct PBXFrameworksBuildPhaseMapperTests {
    @Test("Maps frameworks from frameworks phase")
    func mapFrameworks() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let frameworkRef = try PBXFileReference(
            sourceTree: .group,
            name: "MyFramework.framework",
            path: "Frameworks/MyFramework.framework"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)
        let frameworkBuildFile = PBXBuildFile(file: frameworkRef).add(to: pbxProj)

        let targetFrameworkRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            path: "Target.framework"
        )
        let targetFrameworkBuildFile = PBXBuildFile(file: targetFrameworkRef).add(to: pbxProj)

        let projectTargetPath = xcodeProj.projectPath.parentDirectory.appending(
            components: "AnotherProject",
            "AnotherProject.xcodeproj"
        )
        let projectTargetFrameworkRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            path: "ProjectTarget.framework"
        )
        let projectTargetFrameworkBuildFile = PBXBuildFile(file: projectTargetFrameworkRef).add(to: pbxProj)

        let weakProjectTargetFrameworkRef = PBXFileReference(
            sourceTree: .buildProductsDir,
            path: "WeakProjectTarget.framework"
        )
        let weakProjectTargetFrameworkBuildFile = PBXBuildFile(
            file: weakProjectTargetFrameworkRef,
            settings: ["ATTRIBUTES": ["Weak"]]
        ).add(to: pbxProj)

        let packageProduct = XCSwiftPackageProductDependency(productName: "PackageProduct")
        let packageProductBuildFile = PBXBuildFile(
            product: packageProduct
        ).add(to: pbxProj)

        let frameworksPhase = PBXFrameworksBuildPhase(
            files: [
                frameworkBuildFile,
                targetFrameworkBuildFile,
                projectTargetFrameworkBuildFile,
                weakProjectTargetFrameworkBuildFile,
                packageProductBuildFile,
            ]
        ).add(to: pbxProj)

        try PBXNativeTarget(
            name: "App",
            buildPhases: [frameworksPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        PBXNativeTarget(
            name: "Target",
            buildPhases: [frameworksPhase],
            productType: .framework
        )
        .add(to: pbxProj)

        let mapper = PBXFrameworksBuildPhaseMapper()

        // When
        let frameworks = try await mapper.map(
            frameworksPhase,
            xcodeProj: xcodeProj,
            projectNativeTargets: [
                "ProjectTarget": ProjectNativeTarget(
                    nativeTarget: .test(
                        name: "ProjectTarget"
                    ),
                    project: .test(
                        path: projectTargetPath
                    )
                ),
                "WeakProjectTarget": ProjectNativeTarget(
                    nativeTarget: .test(
                        name: "WeakProjectTarget"
                    ),
                    project: .test(
                        path: projectTargetPath
                    )
                ),
            ]
        )

        // Then
        let frameworkPath = try AbsolutePath(validating: "/tmp/TestProject/Frameworks/MyFramework.framework")
        #expect(
            frameworks.sorted(by: { $0.name < $1.name }) == [
                .framework(
                    path: frameworkPath,
                    status: .required,
                    condition: nil
                ),
                .package(
                    product: "PackageProduct",
                    type: .runtime,
                    condition: nil
                ),
                .project(
                    target: "ProjectTarget",
                    path: projectTargetPath.parentDirectory,
                    status: .required,
                    condition: nil
                ),
                .target(
                    name: "Target",
                    status: .required,
                    condition: nil
                ),
                .project(
                    target: "WeakProjectTarget",
                    path: projectTargetPath.parentDirectory,
                    status: .optional,
                    condition: nil
                ),
            ]
        )
    }

    @Test("Maps SDK frameworks")
    func mapSDKFrameworks() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let accessibilityFrameworkRef = PBXFileReference(
            sourceTree: .sdkRoot,
            path: "Accessibility.framework"
        )
        let accessibilityFrameworkBuildFile = PBXBuildFile(file: accessibilityFrameworkRef).add(to: pbxProj)

        let foundationFrameworkRef = PBXFileReference(
            sourceTree: .developerDir,
            path: "Foundation.framework"
        )
        let foundationFrameworkBuildFile = PBXBuildFile(file: foundationFrameworkRef).add(to: pbxProj)

        let frameworksPhase = PBXFrameworksBuildPhase(
            files: [
                accessibilityFrameworkBuildFile,
                foundationFrameworkBuildFile,
            ]
        ).add(to: pbxProj)

        try PBXNativeTarget(
            name: "App",
            buildPhases: [frameworksPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let mapper = PBXFrameworksBuildPhaseMapper()

        // When
        let frameworks = try mapper.map(
            frameworksPhase,
            xcodeProj: xcodeProj,
            projectNativeTargets: [:]
        )

        // Then
        #expect(
            frameworks.sorted(by: { $0.name < $1.name }) == [
                .sdk(
                    name: "Accessibility",
                    status: .required,
                    condition: nil
                ),
                .sdk(
                    name: "Foundation",
                    status: .required,
                    condition: nil
                ),
            ]
        )
    }
}
