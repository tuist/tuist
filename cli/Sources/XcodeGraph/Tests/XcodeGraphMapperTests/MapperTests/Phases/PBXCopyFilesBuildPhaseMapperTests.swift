import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct PBXCopyFilesBuildPhaseMapperTests {
    @Test("Maps copy files actions, verifying code-sign-on-copy attributes")
    func mapCopyFiles() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let fileRef = try PBXFileReference.test(
            sourceTree: .group,
            name: "MyLibrary.dylib",
            path: "MyLibrary.dylib"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)

        let buildFile = PBXBuildFile(
            file: fileRef,
            settings: ["ATTRIBUTES": ["CodeSignOnCopy"]]
        ).add(to: pbxProj)

        let copyFilesPhase = PBXCopyFilesBuildPhase(
            dstPath: "Libraries",
            dstSubfolderSpec: .frameworks,
            name: "Embed Libraries",
            files: [buildFile]
        )
        .add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            buildPhases: [copyFilesPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let mapper = PBXCopyFilesBuildPhaseMapper()

        // When
        let copyActions = try mapper.map(
            [copyFilesPhase],
            fileSystemSynchronizedGroups: [],
            xcodeProj: xcodeProj
        )

        // Then
        #expect(copyActions.count == 1)

        let action = try #require(copyActions.first)
        #expect(action.name == "Embed Libraries")
        #expect(action.destination == .frameworks)
        #expect(action.subpath == "Libraries")
        #expect(action.files.count == 1)

        let fileAction = try #require(action.files.first)
        #expect(fileAction.codeSignOnCopy == true)
        #expect(fileAction.path.basename == "MyLibrary.dylib")
    }

    @Test("Maps copy files actions with a synchronized group")
    func mapCopyFilesWithSynchronizedGroup() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test(
            path: "/tmp/TestProject/Project.xcodeproj"
        )
        let pbxProj = xcodeProj.pbxproj

        let copyFilesPhase = PBXCopyFilesBuildPhase(
            dstPath: "XPC Services",
            dstSubfolderSpec: .productsDirectory,
            name: "Copy files",
            files: []
        )
        .add(to: pbxProj)

        try PBXNativeTarget.test(
            name: "App",
            buildPhases: [copyFilesPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let mapper = PBXCopyFilesBuildPhaseMapper()
        let exceptionSet = PBXFileSystemSynchronizedGroupBuildPhaseMembershipExceptionSet(
            buildPhase: copyFilesPhase,
            membershipExceptions: [
                "XCPService.xpc",
            ],
            attributesByRelativePath: nil
        )
        let rootGroup = PBXFileSystemSynchronizedRootGroup(
            path: "SynchronizedRootGroup",
            exceptions: [
                exceptionSet,
            ]
        )

        // When
        let copyActions = try mapper.map(
            [copyFilesPhase],
            fileSystemSynchronizedGroups: [
                rootGroup,
            ],
            xcodeProj: xcodeProj
        )

        // Then
        #expect(copyActions.count == 1)

        let action = try #require(copyActions.first)
        #expect(action.name == "Copy files")
        #expect(action.destination == .productsDirectory)
        #expect(action.subpath == "XPC Services")
        #expect(
            action.files == [
                .file(
                    path: "/tmp/TestProject/SynchronizedRootGroup/XCPService.xpc",
                    condition: nil,
                    codeSignOnCopy: true
                ),
            ]
        )
    }
}
