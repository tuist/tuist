import Foundation
import Basic
import ArgumentParser
import TuistCore
import TuistSupport

enum ScaffoldCommandError: FatalError, Equatable {
    var type: ErrorType {
        switch self {
        case .templateNotProvided:
            return .abort
        }
    }

    case templateNotProvided

    var description: String {
        switch self {
        case .templateNotProvided:
            return "You must provide template name"
        }
    }
}

struct ScaffoldCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "scaffold",
                     abstract: "Generates new project based on template",
                     subcommands: [ListCommand.self])
    }
    
    @Option(
        name: .shortAndLong,
        help: "The path to the folder where the template will be generated (Default: Current directory)"
    )
    var path: String?
    
    @Argument(
        help: "Name of template you want to use"
    )
    var template: String
    
    var requiredTemplateOptions: [String: String] = [:]
    var optionalTemplateOptions: [String: String?] = [:]
    
    init() {}

    // Custom decoding to decode dynamic options
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        template = try container.decode(Argument<String>.self, forKey: .template).wrappedValue
        path = try container.decodeIfPresent(Option<String>.self, forKey: .path)?.wrappedValue
        try ScaffoldCommand.requiredTemplateOptions.forEach { option in
            requiredTemplateOptions[option.name] = try container.decode(Option<String>.self,
                                                                        forKey: .required(option.name)).wrappedValue
        }
        try ScaffoldCommand.optionalTemplateOptions.forEach { option in
            optionalTemplateOptions[option.name] = try container.decode(Option<String?>.self,
                                                                        forKey: .optional(option.name)).wrappedValue
        }
    }
    
    func run() throws {
        try ScaffoldService().run(path: path,
                                  templateName: template,
                                  requiredTemplateOptions: requiredTemplateOptions,
                                  optionalTemplateOptions: optionalTemplateOptions)
    }
}

// MARK: - Preprocessing

extension ScaffoldCommand {
    static var requiredTemplateOptions: [(name: String, option: Option<String>)] = []
    static var optionalTemplateOptions: [(name: String, option: Option<String?>)] = []
    
    /// We do not know template's option in advance -> we need to dynamically add them
    static func preprocess(_ arguments: [String]? = nil) throws {
        guard
            let arguments = arguments,
            arguments.count >= 2
        else { throw ScaffoldCommandError.templateNotProvided }
        // We want to parse only the name of template, not its arguments which will be dynamically added
        // Plucking out path argument
        let pairedArguments: [[String]] = stride(from: 2, to: arguments.count, by: 2).map {
            Array(arguments[$0 ..< min($0 + 2, arguments.count)])
        }
        let filteredArguments = pairedArguments
        .filter {
            $0.first == "--path" || $0.first == "-p"
        }
        .flatMap { $0 }
        
        guard let command = try parseAsRoot([arguments[1]] + filteredArguments) as? ScaffoldCommand else { return }
        
        let (required, optional) = try ScaffoldService().loadTemplateOptions(templateName: command.template,
                                                                             path: command.path)
        
        ScaffoldCommand.requiredTemplateOptions = required.map {
            (name: $0, option: Option<String>(name: .shortAndLong))
        }
        ScaffoldCommand.optionalTemplateOptions = optional.map {
            (name: $0, option: Option<String?>(name: .shortAndLong))
        }
    }
}

// MARK: - ScaffoldCommand.CodingKeys
extension ScaffoldCommand {
    enum CodingKeys: CodingKey {
        case template
        case path
        case required(String)
        case optional(String)
        
        var stringValue: String {
            switch self {
            case .template:
                return "template"
            case .path:
                return "path"
            case let .required(required):
                return required
            case let .optional(optional):
                return optional
            }
        }
        
        // Not used
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }
        init?(stringValue: String) { nil }
    }
}

/// ArgumentParser library gets the list of options from a mirror
/// Since we do not declare template's options in advance, we need to rewrite the mirror implementation and add them ourselves
extension ScaffoldCommand: CustomReflectable {
    var customMirror: Mirror {
        let requiredTemplateChildren = ScaffoldCommand.requiredTemplateOptions
            .map { Mirror.Child(label: $0.name, value: $0.option) }
        let optionalTemplateChildren = ScaffoldCommand.optionalTemplateOptions
            .map { Mirror.Child(label: $0.name, value: $0.option) }
        let children = [
            Mirror.Child(label: "template", value: _template),
            Mirror.Child(label: "path", value: _path),
        ]
        return Mirror(ScaffoldCommand.init(), children: children + requiredTemplateChildren + optionalTemplateChildren)
    }
}
