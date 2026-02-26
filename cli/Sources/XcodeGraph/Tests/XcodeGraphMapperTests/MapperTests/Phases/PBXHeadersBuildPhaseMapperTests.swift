import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct PBXHeadersBuildPhaseMapperTests {
    @Test("Maps public, private, and project headers from headers phase")
    func mapHeaders() async throws {
        // Given
        let xcodeProj = try await XcodeProj.test()
        let pbxProj = xcodeProj.pbxproj

        let publicHeaderRef = try PBXFileReference.test(
            name: "PublicHeader.h",
            path: "Include/PublicHeader.h"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)

        let publicBuildFile = PBXBuildFile(
            file: publicHeaderRef,
            settings: ["ATTRIBUTES": ["Public"]]
        ).add(to: pbxProj)

        let privateHeaderRef = try PBXFileReference.test(
            name: "PrivateHeader.h",
            path: "Include/PrivateHeader.h"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)

        let privateBuildFile = PBXBuildFile(
            file: privateHeaderRef,
            settings: ["ATTRIBUTES": ["Private"]]
        ).add(to: pbxProj)

        let projectHeaderRef = try PBXFileReference.test(
            name: "ProjectHeader.h",
            path: "Include/ProjectHeader.h"
        )
        .add(to: pbxProj)
        .addToMainGroup(in: pbxProj)

        let projectBuildFile = PBXBuildFile(file: projectHeaderRef).add(to: pbxProj)

        let headersPhase = PBXHeadersBuildPhase(
            files: [publicBuildFile, privateBuildFile, projectBuildFile]
        )
        .add(to: pbxProj)

        try PBXNativeTarget(
            name: "App",
            buildPhases: [headersPhase],
            productType: .application
        )
        .add(to: pbxProj)
        .add(to: pbxProj.rootObject)

        let mapper = PBXHeadersBuildPhaseMapper()

        // When
        let headers = try mapper.map(headersPhase, xcodeProj: xcodeProj)

        // Then
        try #require(headers != nil)
        #expect(headers?.public.map(\.basename).contains("PublicHeader.h") == true)
        #expect(headers?.private.map(\.basename).contains("PrivateHeader.h") == true)
        #expect(headers?.project.map(\.basename).contains("ProjectHeader.h") == true)
    }
}
