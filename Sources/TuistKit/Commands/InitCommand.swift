import Basic
import Foundation
import ArgumentParser
import TuistCore
import TuistGenerator
import TuistLoader
import TuistScaffold
import TuistSupport

private typealias Platform = TuistCore.Platform
private typealias Product = TuistCore.Product

struct InitCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "init",
                             abstract: "Bootstraps a project")
    }

    @Option(
        name: .shortAndLong,
        help: "The platform (ios, tvos or macos) the product will be for (Default: ios)"
    )
    var platform: String?
    
    @Option(
        name: .shortAndLong,
        help: "The path to the folder where the project will be generated (Default: Current directory)"
    )
    var path: String?
    
    @Option(
        name: .shortAndLong,
        help: "The name of the project. If it's not passed (Default: Name of the directory)"
    )
    var name: String?
    
    @Option(
        name: .shortAndLong,
        help: "The name of the template to use (you can list available templates with tuist scaffold list)"
    )
    var template: String?
    
    var requiredTemplateOptions: [String: String] = [:]
    var optionalTemplateOptions: [String: String?] = [:]
    
    init() {}

    // Custom decoding to decode dynamic options
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decodeIfPresent(Option<String>.self, forKey: .platform)?.wrappedValue
        name = try container.decodeIfPresent(Option<String>.self, forKey: .name)?.wrappedValue
        template = try container.decodeIfPresent(Option<String>.self, forKey: .template)?.wrappedValue
        path = try container.decodeIfPresent(Option<String>.self, forKey: .path)?.wrappedValue
        try InitCommand.requiredTemplateOptions.forEach { option in
            requiredTemplateOptions[option.name] = try container.decode(Option<String>.self,
                                                                        forKey: .required(option.name)).wrappedValue
        }
        try InitCommand.optionalTemplateOptions.forEach { option in
            optionalTemplateOptions[option.name] = try container.decode(Option<String?>.self,
                                                                        forKey: .optional(option.name)).wrappedValue
        }
    }

    func run() throws {
        try InitService().run(name: name,
                              platform: platform,
                              path: path,
                              templateName: template,
                              requiredTemplateOptions: requiredTemplateOptions,
                              optionalTemplateOptions: optionalTemplateOptions)
    }
}

// MARK: - Preprocessing
extension InitCommand {
    static var requiredTemplateOptions: [(name: String, option: Option<String>)] = []
    static var optionalTemplateOptions: [(name: String, option: Option<String?>)] = []
    
    /// We do not know template's option in advance -> we need to dynamically add them
    static func preprocess(_ arguments: [String]? = nil) throws {
        guard
            let arguments = arguments,
            arguments.contains("--template")
        else { return }
        
        // We want to parse only the name of template, not its arguments which will be dynamically added
        // Plucking out path argument
        let pairedArguments: [[String]] = stride(from: 1, to: arguments.count, by: 2).map {
            Array(arguments[$0 ..< min($0 + 2, arguments.count)])
        }
        let possibleValues = ["--path", "-p", "--template", "-t"]
        let filteredArguments = pairedArguments
        .filter {
            possibleValues.contains($0.first ?? "")
        }
        .flatMap { $0 }
        
        guard
            let command = try parseAsRoot(filteredArguments) as? InitCommand,
            let templateName = command.template,
            templateName != "default"
        else { return }
        
        let (required, optional) = try InitService().loadTemplateOptions(templateName: templateName,
                                                                         path: command.path)
        
        InitCommand.requiredTemplateOptions = required.map {
            (name: $0, option: Option<String>(name: .shortAndLong))
        }
        InitCommand.optionalTemplateOptions = optional.map {
            (name: $0, option: Option<String?>(name: .shortAndLong))
        }
    }
}

// MARK: - InitCommand.CodingKeys
extension InitCommand {
    enum CodingKeys: CodingKey {
        case platform
        case name
        case template
        case path
        case required(String)
        case optional(String)
        
        var stringValue: String {
            switch self {
            case .platform:
                return "plaform"
            case .name:
                return "name"
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
extension InitCommand: CustomReflectable {
    var customMirror: Mirror {
        let requiredTemplateChildren = InitCommand.requiredTemplateOptions
            .map { Mirror.Child(label: $0.name, value: $0.option) }
        let optionalTemplateChildren = InitCommand.optionalTemplateOptions
            .map { Mirror.Child(label: $0.name, value: $0.option) }
        let children = [
            Mirror.Child(label: "platform", value: _platform),
            Mirror.Child(label: "name", value: _name),
            Mirror.Child(label: "template", value: _template),
            Mirror.Child(label: "path", value: _path),
        ]
        return Mirror(InitCommand.init(), children: children + requiredTemplateChildren + optionalTemplateChildren)
    }
}


//    func parse(with parser: ArgumentParser, arguments: [String]) throws -> ArgumentParser.Result {
//        guard arguments.contains("--template") else { return try parser.parse(arguments) }
//        // Plucking out path and template argument
//        let pairedArguments = stride(from: 1, to: arguments.count, by: 2).map {
//            arguments[$0 ..< min($0 + 2, arguments.count)]
//        }
//        let filteredArguments = pairedArguments
//            .filter {
//                $0.first == "--path" || $0.first == "--template"
//            }
//            .flatMap { Array($0) }
//        // We want to parse only the name of template, not its arguments which will be dynamically added
//        let resultArguments = try parser.parse(Array(arguments.prefix(1)) + filteredArguments)
//
//        guard let templateName = resultArguments.get(templateArgument) else { throw InitCommandError.templateNotProvided }
//
//        let path = self.path(arguments: resultArguments)
//        let directories = try templatesDirectoryLocator.templateDirectories(at: path)
//
//        let templateDirectory = try self.templateDirectory(templateDirectories: directories,
//                                                           template: templateName)
//
//        let template = try templateLoader.loadTemplate(at: templateDirectory)
//
//        // Dynamically add attributes from template to `subParser`
//        attributesArguments = template.attributes.reduce([:]) {
//            var mutableDictionary = $0
//            mutableDictionary[$1.name] = subParser.add(option: "--\($1.name)",
//                                                       kind: String.self)
//            return mutableDictionary
//        }
//
//        return try parser.parse(arguments)
//    }
