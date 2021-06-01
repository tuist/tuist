import ArgumentParser
import Foundation
import TuistSupport

enum ExecCommandError: FatalError, Equatable {
    case taskNotProvided

    var description: String {
        switch self {
        case .taskNotProvided:
            return "You must provide a task name."
        }
    }

    var type: ErrorType {
        switch self {
        case .taskNotProvided:
            return .bug
        }
    }
}

struct ExecCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "exec",
            abstract: "Runs a task defined in Tuist/Tasks directory."
        )
    }

    @Argument(
        help: "Name of a task you want to run."
    )
    var task: String

    @Option(
        name: .shortAndLong,
        help: "The path to the directory where the tasks are run from.",
        completion: .directory
    )
    var path: String?

    func run() throws {
        try ExecService().run(
            task,
            options: taskOptions,
            path: path
        )
    }

    init() {}

    var taskOptions: [String: String] = [:]

    // Custom decoding to decode dynamic options
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        task = try container.decode(Argument<String>.self, forKey: .task).wrappedValue
        path = try container.decodeIfPresent(Option<String>.self, forKey: .path)?.wrappedValue
        try ExecCommand.options.forEach { option in
            guard let value = try container.decode(
                Option<String?>.self,
                forKey: .option(option.name)
            )
            .wrappedValue
            else { return }
            taskOptions[option.name] = value
        }
    }
}

// MARK: - Preprocessing

extension ExecCommand {
    static var options: [(name: String, option: Option<String?>)] = []

    /// We do not know template's option in advance -> we need to dynamically add them
    static func preprocess(_ arguments: [String]? = nil) throws {
        guard
            let arguments = arguments,
            arguments.count >= 2
        else { throw ExecCommandError.taskNotProvided }
        guard !configuration.subcommands.contains(where: { $0.configuration.commandName == arguments[1] }) else { return }
        // We want to parse only the name of a task, not its arguments which will be dynamically added
        // Plucking out path arguments
        let pairedArguments: [[String]] = stride(from: 2, to: arguments.count, by: 2).map {
            Array(arguments[$0 ..< min($0 + 2, arguments.count)])
        }
        let filteredArguments = pairedArguments
            .filter {
                $0.first == "--path" || $0.first == "-p"
            }
            .flatMap { $0 }

        guard let command = try parseAsRoot([arguments[1]] + filteredArguments) as? ExecCommand else { return }

        ExecCommand.options = try ExecService().loadTaskOptions(
            taskName: command.task,
            path: command.path
        )
        .map {
            (name: $0, option: Option<String?>())
        }
    }
}

// MARK: - TaskCommand.CodingKeys

extension ExecCommand {
    enum CodingKeys: CodingKey {
        case task
        case path
        case option(String)

        var stringValue: String {
            switch self {
            case .task:
                return "task"
            case .path:
                return "path"
            case let .option(option):
                return option
            }
        }

        init?(stringValue: String) {
            switch stringValue {
            case "task":
                self = .task
            case "path":
                self = .path
            default:
                if ExecCommand.options.map(\.name).contains(stringValue) {
                    self = .option(stringValue)
                } else {
                    return nil
                }
            }
        }

        // Not used
        var intValue: Int? { nil }
        init?(intValue _: Int) { nil }
    }
}

/// ArgumentParser library gets the list of options from a mirror.
/// Since we do not declare task's options in advance, we need to rewrite the mirror implementation and add them ourselves.
extension ExecCommand: CustomReflectable {
    var customMirror: Mirror {
        let optionsChildren = ExecCommand.options
            .map { Mirror.Child(label: $0.name, value: $0.option) }
        let children = [
            Mirror.Child(label: "task", value: _task),
            Mirror.Child(label: "path", value: _path),
        ]
        .filter {
            // Prefer attributes defined in a template if it clashes with predefined ones
            $0.label.map { label in
                !ExecCommand.options.map(\.name)
                    .contains(label)
            } ?? true
        }
        return Mirror(ExecCommand(), children: children + optionsChildren)
    }
}
