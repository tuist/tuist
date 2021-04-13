import Foundation
import ArgumentParser


enum TaskCommandError: FatalError, Equatable {
    var type: ErrorType {
        switch self {
        case .taskNotProvided:
            return .abort
        }
    }

    case taskNotProvided

    var description: String {
        switch self {
        case .taskNotProvided:
            return "You must provide task name"
        }
    }
}


struct TaskCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "task",
            abstract: "Runs task defined in Tasks.swift",
        )
    }
    
    @Argument(
        help: "Name of a task you want to run"
    )
    var task: String
    
    func run() throws {
        TaskService().run(task)
    }
}
