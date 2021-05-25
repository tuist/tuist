import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
import TuistSupportTesting
import TuistLoaderTesting
import TuistTasksTesting

@testable import TuistKit

final class TaskServiceTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoader!
    private var tasksLocator: MockTasksLocator!
    private var subject: TaskService!
    
    override func setUp() {
        super.setUp()
        manifestLoader = MockManifestLoader()
        tasksLocator = MockTasksLocator()
        subject = TaskService(
            manifestLoader: manifestLoader,
            tasksLocator: tasksLocator
        )
    }
    
    override func tearDown() {
        manifestLoader = nil
        tasksLocator = nil
        subject = nil
        
        super.tearDown()
    }
    
    func test_load_task_options_when_task_not_found() throws {
        // Given
        let path = try temporaryPath()
        tasksLocator.locateTasksStub = { path in
            [
                path.appending(component: "TaskB.swift"),
                path.appending(component: "TaskC.swift"),
            ]
        }

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.loadTaskOptions(taskName: "task-a", path: path.pathString),
            TaskError.taskNotFound("task-a", ["task-b", "task-c"])
        )
    }
    
    func test_load_task_options_when_none() throws {
        // Given
        let path = try temporaryPath()
        let taskPath = path.appending(component: "TaskA.swift")
        try fileHandler.write(
            """
           import ProjectAutomation
           import Foundation
        
           let task = Task(
               options: [
               ]
           ) { options in
                // some task code
           }
        
        """,
            path: taskPath,
            atomically: true
        )
        tasksLocator.locateTasksStub = { path in
            [
                path.appending(component: "TaskA.swift"),
                path.appending(component: "TaskB.swift"),
            ]
        }
        
        // When / Then
        XCTAssertEmpty(
            try subject.loadTaskOptions(
                taskName: "task-a",
                path: path.pathString
            )
        )
    }
    
    func test_load_task_options_when_defined_on_single_line() throws {
        // Given
        let path = try temporaryPath()
        let taskPath = path.appending(component: "TaskA.swift")
        try fileHandler.write(
            """
           import ProjectAutomation
           import Foundation
        
           let task = Task(
               options: [.option("option-a"), .option("option-b")]
           ) { options in
                // some task code
           }
        
        """,
            path: taskPath,
            atomically: true
        )
        tasksLocator.locateTasksStub = { path in
            [
                path.appending(component: "TaskA.swift"),
                path.appending(component: "TaskB.swift"),
            ]
        }
        
        // When / Then
        XCTAssertEqual(
            try subject.loadTaskOptions(
                taskName: "task-a",
                path: path.pathString
            ),
            [
                "option-a",
                "option-b",
            ]
        )
    }
    
    func test_load_task_options_when_defined_on_multiple_lines() throws {
        // Given
        let path = try temporaryPath()
        let taskPath = path.appending(component: "TaskA.swift")
        try fileHandler.write(
            """
           import ProjectAutomation
           import Foundation
        
           let task = Task(
               options: [
                    .option("option-a"),
                    .option("option-b")
                ]
           ) { options in
                // some task code
           }
        
        """,
            path: taskPath,
            atomically: true
        )
        tasksLocator.locateTasksStub = { path in
            [
                path.appending(component: "TaskA.swift"),
                path.appending(component: "TaskB.swift"),
            ]
        }
        
        // When / Then
        XCTAssertEqual(
            try subject.loadTaskOptions(
                taskName: "task-a",
                path: path.pathString
            ),
            [
                "option-a",
                "option-b",
            ]
        )
    }
    
    func test_run_when_task_not_found() throws {
        // Given
        let path = try temporaryPath()
        tasksLocator.locateTasksStub = { path in
            [
                path.appending(component: "TaskB.swift"),
                path.appending(component: "TaskC.swift"),
            ]
        }

        // When / Then
        XCTAssertThrowsSpecific(
            try subject.run("task-a", options: [:], path: path.pathString),
            TaskError.taskNotFound("task-a", ["task-b", "task-c"])
        )
    }
    
    func test_run_when_task_found() throws {
        // Given
        let path = try temporaryPath()
        let taskPath = path.appending(component: "TaskA.swift")
        tasksLocator.locateTasksStub = { path in
            [
                path.appending(component: "TaskA.swift"),
                path.appending(component: "TaskB.swift"),
                path.appending(component: "TaskC.swift"),
            ]
        }
        manifestLoader.taskLoadArgumentsStub = {
            [
                "load",
                $0.pathString,
            ]
        }
        system.succeedCommand(
            "load",
            taskPath.pathString,
            "--tuist-task",
            "{\"option-a\":\"Value\"}"
        )

        // When / Then
        XCTAssertNoThrow(
            try subject.run(
                "task-a",
                options: ["option-a": "Value"],
                path: path.pathString
            )
        )
    }
}
