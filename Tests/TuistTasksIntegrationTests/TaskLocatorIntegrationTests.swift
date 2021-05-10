import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import TuistSupportTesting
import XCTest

@testable import TuistTasks

final class TasksLocatorIntegrationTests: TuistTestCase {
    var subject: TasksLocator!

    override func setUp() {
        super.setUp()
        subject = TasksLocator()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_locate_when_a_tasks_directory_exists() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory", "this/is/Tuist/Tasks"])
        let tasksPath = temporaryDirectory.appending(RelativePath("this/is/Tuist/Tasks"))
        try createFiles(
            [
                "this/is/Tuist/Tasks/TaskA.swift",
                "this/is/Tuist/Tasks/TaskB.swift",
            ]
        )

        // When
        let got = try subject.locateTasks(at: temporaryDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEqual(
            got.sorted(),
            [
                tasksPath.appending(component: "TaskA.swift"),
                tasksPath.appending(component: "TaskB.swift"),
            ]
        )
    }

    func test_locate_when_a_tasks_directory_does_not_exist() throws {
        // Given
        let temporaryDirectory = try temporaryPath()
        try createFolders(["this/is/a/very/nested/directory"])

        // When
        let got = try subject.locateTasks(at: temporaryDirectory.appending(RelativePath("this/is/a/very/nested/directory")))

        // Then
        XCTAssertEmpty(got)
    }
}
