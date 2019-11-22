import Basic
import Foundation
import TuistCore
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class ProjectEditorTests: TuistUnitTestCase {
    var generator: MockGenerator!
    var projectEditorMapper: MockProjectEditorMapper!
    var resourceLocator: MockResourceLocator!
    var manifestFilesLocator: MockManifestFilesLocator!
    var helpersDirectoryLocator: MockHelpersDirectoryLocator!
    var subject: ProjectEditor!

    override func setUp() {
        super.setUp()
        generator = MockGenerator()
        projectEditorMapper = MockProjectEditorMapper()
        resourceLocator = MockResourceLocator()
        manifestFilesLocator = MockManifestFilesLocator()
        helpersDirectoryLocator = MockHelpersDirectoryLocator()
        subject = ProjectEditor(generator: generator,
                                projectEditorMapper: projectEditorMapper,
                                resourceLocator: resourceLocator,
                                manifestFilesLocator: manifestFilesLocator,
                                helpersDirectoryLocator: helpersDirectoryLocator)
    }

    override func tearDown() {
        super.tearDown()
        generator = nil
        projectEditorMapper = nil
        resourceLocator = nil
        manifestFilesLocator = nil
        helpersDirectoryLocator = nil
        subject = nil
    }

    func test_edit() throws {
        // Given
        let directory = try temporaryPath()
        let projectDescriptionPath = directory.appending(component: "ProjectDescription.framework")
        let project = Project.test(path: directory, name: "Edit")
        let graph = Graph.test(name: "Edit")
        let helpersDirectory = directory.appending(component: "ProjectDDescriptionHelpers")
        try FileHandler.shared.createFolder(helpersDirectory)
        let helpers = ["A.swift", "B.swift"].map { helpersDirectory.appending(component: $0) }
        try helpers.forEach { try FileHandler.shared.touch($0) }
        let manifests: [(Manifest, AbsolutePath)] = [(.project, directory.appending(component: "Project.swift"))]

        resourceLocator.projectDescriptionStub = { projectDescriptionPath }
        manifestFilesLocator.locateStub = manifests
        helpersDirectoryLocator.locateStub = helpersDirectory
        projectEditorMapper.mapStub = (project, graph)
        var generatedProject: Project?
        generator.generateProjectStub = { project in
            generatedProject = project
            return directory.appending(component: "Edit.xcodeproj")
        }

        // When
        try subject.edit(at: directory, in: directory)

        // Then
        XCTAssertEqual(projectEditorMapper.mapArgs.count, 1)
        let mapArgs = projectEditorMapper.mapArgs.first
        XCTAssertEqual(mapArgs?.helpers, helpers)
        XCTAssertEqual(mapArgs?.sourceRootPath, directory)
        XCTAssertEqual(mapArgs?.projectDescriptionPath, projectDescriptionPath)

        XCTAssertEqual(generatedProject, project)
    }
}
