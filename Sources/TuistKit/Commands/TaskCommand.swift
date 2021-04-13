import Foundation
import ArgumentParser

struct TaskCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "task",
            abstract: "Runs task defined in Tasks.swift"
        )
    }
    
    @Argument(
        help: "Name of a task you want to run"
    )
    var task: String
    
    @Option(
        name: .shortAndLong,
        help: "The path to the directory where the tasks are run from",
        completion: .directory
    )
    var path: String?
    
    func run() throws {
        try TaskService().run(
            task,
            path: path
        )
    }
}
