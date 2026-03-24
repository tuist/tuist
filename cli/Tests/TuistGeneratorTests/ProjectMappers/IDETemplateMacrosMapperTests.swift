import Foundation
import Path
import Testing
import TuistCore
import TuistGenerator
import TuistTesting
import XcodeGraph

struct IDETemplateMacrosMapperTests {
    let subject: IDETemplateMacrosMapper
    init() {
        subject = IDETemplateMacrosMapper()
    }

    @Test
    func project_map_template_macros_creates_macros_plist() throws {
        // Given
        let templateMacros = IDETemplateMacros.test()
        let project = Project.test(ideTemplateMacros: templateMacros)

        // When
        let (got, sideEffects) = try subject.map(project: project)

        // Then
        #expect(got == project)

        #expect(sideEffects == [
            .file(
                .init(
                    path: project.xcodeProjPath.appending(try RelativePath(validating: "xcshareddata/IDETemplateMacros.plist")),
                    contents: try PropertyListEncoder().encode(templateMacros),
                    state: .present
                )
            ),
        ])
    }

    @Test
    func project_map_empty_template_macros() throws {
        // Given
        let project = Project.empty()

        // When
        let (got, sideEffects) = try subject.map(project: project)

        // Then
        #expect(got == project)
        #expect(sideEffects.isEmpty)
    }

    @Test
    func workspace_map_template_macros_creates_macros_plist() throws {
        // Given
        let templateMacros = IDETemplateMacros.test()
        let workspace = Workspace.test(ideTemplateMacros: templateMacros)
        let workspaceWithProjects = WorkspaceWithProjects.test(workspace: workspace)

        // When
        let (got, sideEffects) = try subject.map(workspace: workspaceWithProjects)

        // Then
        #expect(got == workspaceWithProjects)

        #expect(sideEffects == [
            .file(
                .init(
                    path: workspace.xcWorkspacePath
                        .appending(try RelativePath(validating: "xcshareddata/IDETemplateMacros.plist")),
                    contents: try PropertyListEncoder().encode(templateMacros),
                    state: .present
                )
            ),
        ])
    }

    @Test
    func workspace_map_empty_template_macros() throws {
        // Given
        let workspace = Workspace.test(ideTemplateMacros: nil)
        let workspaceWithProjects = WorkspaceWithProjects.test(workspace: workspace)

        // When
        let (got, sideEffects) = try subject.map(workspace: workspaceWithProjects)

        // Then
        #expect(got == workspaceWithProjects)
        #expect(sideEffects.isEmpty)
    }
}
