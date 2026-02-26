import Foundation
import Path
import PathKit
import Testing
import XcodeGraph
import XcodeProj
@testable import XcodeGraphMapper

@Suite
struct XCWorkspaceMapperTests {
    @Test("Maps workspace without any projects or schemes")
    func map_NoProjectsOrSchemes() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/MyWorkspace.xcworkspace")
        let xcworkspace: XCWorkspace = .test(files: ["ReadMe.md"], path: workspacePath.pathString)
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.name == "MyWorkspace")
        #expect(workspace.projects.isEmpty == true)
        #expect(workspace.schemes.isEmpty == true)
    }

    @Test("Maps workspace with multiple projects")
    func map_MultipleProjects() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/MyWorkspace.xcworkspace")
        let workspaceDir = workspacePath.parentDirectory
        let xcworkspace: XCWorkspace = .test(
            withElements: [
                .test(relativePath: "ProjectA.xcodeproj"),
                .group(XCWorkspaceDataGroup(
                    location: .group("NestedGroup"),
                    name: "NestedGroup",
                    children: [
                        .test(relativePath: "ProjectB.xcodeproj"),
                        .test(relativePath: "Notes.txt"),
                    ]
                )),
            ], path: workspacePath.pathString
        )
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.name == "MyWorkspace")
        #expect(workspace.projects.count == 2)
        #expect(workspace.projects.contains(workspaceDir.appending(component: "ProjectA.xcodeproj")) == true)
        #expect(workspace.projects.contains(workspaceDir.appending(components: ["NestedGroup", "ProjectB.xcodeproj"])) == true)
        #expect(workspace.schemes.isEmpty == true)
    }

    @Test("Maps workspace with shared schemes")
    func map_WithSchemes() async throws {
        // Given
        let tempDirectory = FileManager.default.temporaryDirectory
        let path = tempDirectory.appendingPathComponent("MyWorkspace.xcworkspace")
        let workspacePath = try AbsolutePath(validating: path.path)
        let sharedDataDir = workspacePath.pathString + "/xcshareddata/xcschemes"
        try FileManager.default.createDirectory(atPath: sharedDataDir, withIntermediateDirectories: true)
        let schemeFile = sharedDataDir + "/MyScheme.xcscheme"
        try "dummy scheme content".write(toFile: schemeFile, atomically: true, encoding: .utf8)

        let xcworkspace: XCWorkspace = .test(withElements: [.test(relativePath: "App.xcodeproj")], path: workspacePath.pathString)
        let mapper = XCWorkspaceMapper()

        // When / Then
        // We expect an XML parser error due to dummy content.
        do {
            _ = try await mapper.map(xcworkspace: xcworkspace)
        } catch {
            #expect(error.localizedDescription == "The operation couldn’t be completed. (NSXMLParserErrorDomain error 4.)")
        }
    }

    @Test("No schemes directory results in no schemes mapped")
    func map_NoSchemesDirectory() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/MyWorkspace.xcworkspace")
        let xcworkspace = XCWorkspace.test(withElements: [
            .test(relativePath: "App.xcodeproj"),
        ], path: workspacePath.pathString)
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.schemes.isEmpty == true)
    }

    @Test("Workspace name is derived from the .xcworkspace file name")
    func map_NameDerivation() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/AnotherWorkspace.xcworkspace")
        let xcworkspace = XCWorkspace.test(withElements: [], path: workspacePath.pathString)
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.name == "AnotherWorkspace")
    }

    @Test("Resolves absolute path in XCWorkspaceDataFileRef")
    func map_AbsolutePath() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/AbsWorkspace.xcworkspace")
        let elements: [XCWorkspaceDataElement] = [
            .file(XCWorkspaceDataFileRef(location: .absolute("/Users/SomeUser/ProjectC.xcodeproj"))),
        ]
        let xcworkspace = XCWorkspace(data: XCWorkspaceData(children: elements), path: .init(workspacePath.pathString))
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.projects.isEmpty == false)
    }

    @Test("Resolves container path in XCWorkspaceDataFileRef")
    func map_ContainerPath() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/ContainerWorkspace.xcworkspace")
        let elements: [XCWorkspaceDataElement] = [
            .file(XCWorkspaceDataFileRef(location: .container("Nested/ProjectD.xcodeproj"))),
        ]
        let xcworkspace = XCWorkspace(data: XCWorkspaceData(children: elements), path: .init(workspacePath.pathString))
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.projects.isEmpty == false)
    }

    @Test("Resolves developer path in XCWorkspaceDataFileRef")
    func map_DeveloperPath() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/DevWorkspace.xcworkspace")
        let elements: [XCWorkspaceDataElement] = [
            .file(XCWorkspaceDataFileRef(location: .developer("Platforms/iPhoneOS.platform/Developer/ProjectE.xcodeproj"))),
        ]
        let xcworkspace = XCWorkspace(data: XCWorkspaceData(children: elements), path: .init(workspacePath.pathString))
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.projects.isEmpty == false)
    }

    @Test("Resolves group path in XCWorkspaceDataFileRef")
    func map_GroupPath() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/GroupWorkspace.xcworkspace")
        let elements: [XCWorkspaceDataElement] = [
            .group(XCWorkspaceDataGroup(location: .group("MyGroup"), name: "MyGroup", children: [
                .file(XCWorkspaceDataFileRef(location: .group("Subfolder/ProjectF.xcodeproj"))),
            ])),
        ]
        let xcworkspace = XCWorkspace(data: XCWorkspaceData(children: elements), path: .init(workspacePath.pathString))
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.projects.isEmpty == false)
    }

    @Test("Resolves current path in XCWorkspaceDataFileRef")
    func map_CurrentPath() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/CurrentWorkspace.xcworkspace")
        let elements: [XCWorkspaceDataElement] = [
            .file(XCWorkspaceDataFileRef(location: .current("RelativePath/ProjectG.xcodeproj"))),
        ]
        let xcworkspace = XCWorkspace(data: XCWorkspaceData(children: elements), path: .init(workspacePath.pathString))
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.projects.isEmpty == false)
    }

    @Test("Resolves other path in XCWorkspaceDataFileRef")
    func map_otherPath() async throws {
        // Given
        let workspacePath = try AbsolutePath(validating: "/tmp/OtherWorkspace.xcworkspace")
        let elements: [XCWorkspaceDataElement] = [
            .file(XCWorkspaceDataFileRef(location: .other("customscheme", "Path/ProjectH.xcodeproj"))),
        ]
        let xcworkspace = XCWorkspace(data: XCWorkspaceData(children: elements), path: .init(workspacePath.pathString))
        let mapper = XCWorkspaceMapper()

        // When
        let workspace = try await mapper.map(xcworkspace: xcworkspace)

        // Then
        #expect(workspace.projects.isEmpty == false)
    }
}
