import AnyCodable
import ArgumentParser
import Foundation
import Path
import TuistCore
import TuistGenerator
import TuistLoader
import TuistScaffold
import TuistSupport
import XcodeGraph

private typealias Platform = XcodeGraph.Platform
private typealias Product = XcodeGraph.Product

public struct InitCommand: AsyncParsableCommand, HasTrackableParameters {
    public static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "init",
            abstract: "Bootstraps a project"
        )
    }

    public static var analyticsDelegate: TrackableParametersDelegate?
    public var runId = UUID().uuidString

    @Option(
        help: "The platform (ios, tvos, visionos, watchos or macos) the product will be for (Default: ios)",
        completion: .list(["ios", "tvos", "macos", "visionos", "watchos"]),
        envKey: .initPlatform
    )
    var platform: String?

    @Option(
        name: .shortAndLong,
        help: "The path to the folder where the project will be generated. (Default: Current directory)",
        completion: .directory,
        envKey: .initPath
    )
    var path: String?

    @Option(
        name: .shortAndLong,
        help: "The name of the project. (Default: Name of the current directory)",
        envKey: .initName
    )
    var name: String?

    @Option(
        name: .shortAndLong,
        help: "The name of the template to use (you can list available templates with tuist scaffold list)",
        envKey: .initTemplate
    )
    var template: String?

    var requiredTemplateOptions: [String: String] = [:]
    var optionalTemplateOptions: [String: String?] = [:]

    public init() {}

    // Custom decoding to decode dynamic options
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = try container.decodeIfPresent(Option<String>.self, forKey: .platform)?.wrappedValue
        name = try container.decodeIfPresent(Option<String>.self, forKey: .name)?.wrappedValue
        template = try container.decodeIfPresent(Option<String>.self, forKey: .template)?.wrappedValue
        path = try container.decodeIfPresent(Option<String>.self, forKey: .path)?.wrappedValue
        for option in InitCommand.requiredTemplateOptions {
            requiredTemplateOptions[option.name] = try container.decode(
                Option<String>.self,
                forKey: .required(option.name)
            ).wrappedValue
        }
        for option in InitCommand.optionalTemplateOptions {
            optionalTemplateOptions[option.name] = try container.decode(
                Option<String?>.self,
                forKey: .optional(option.name)
            ).wrappedValue
        }
    }

    public func run() async throws {
        InitCommand.analyticsDelegate?.addParameters(
            [
                "platform": AnyCodable(platform ?? "unknown"),
            ]
        )
        try await InitService().run(
            name: name,
            platform: platform,
            path: path,
            templateName: template,
            requiredTemplateOptions: requiredTemplateOptions,
            optionalTemplateOptions: optionalTemplateOptions
        )
    }
}

// MARK: - Preprocessing

extension InitCommand {
    static var requiredTemplateOptions: [(name: String, option: Option<String>)] = []
    static var optionalTemplateOptions: [(name: String, option: Option<String?>)] = []

    /// We do not know template's option in advance -> we need to dynamically add them
    static func preprocess(_ arguments: [String]? = nil) async throws {
        guard let arguments,
              arguments.contains("--template") ||
              arguments.contains("-t")
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

        guard let command = try parseAsRoot(filteredArguments) as? InitCommand,
              let templateName = command.template,
              templateName != "default"
        else { return }

        let (required, optional) = try await InitService().loadTemplateOptions(
            templateName: templateName,
            path: command.path
        )

        InitCommand.requiredTemplateOptions = required.map {
            (name: $0, option: Option<String>())
        }
        InitCommand.optionalTemplateOptions = optional.map {
            (name: $0, option: Option<String?>())
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
                return "platform"
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

        init?(stringValue: String) {
            switch stringValue {
            case "platform":
                self = .platform
            case "name":
                self = .name
            case "template":
                self = .template
            case "path":
                self = .path
            default:
                if InitCommand.requiredTemplateOptions.map(\.name).contains(stringValue) {
                    self = .required(stringValue)
                } else if InitCommand.optionalTemplateOptions.map(\.name).contains(stringValue) {
                    self = .optional(stringValue)
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

/// ArgumentParser library gets the list of options from a mirror
/// Since we do not declare template's options in advance, we need to rewrite the mirror implementation and add them ourselves
extension InitCommand: CustomReflectable {
    public var customMirror: Mirror {
        let requiredTemplateChildren = InitCommand.requiredTemplateOptions
            .map { Mirror.Child(label: $0.name, value: $0.option) }
        let optionalTemplateChildren = InitCommand.optionalTemplateOptions
            .map { Mirror.Child(label: $0.name, value: $0.option) }

        let children = [
            Mirror.Child(label: "platform", value: _platform),
            Mirror.Child(label: "name", value: _name),
            Mirror.Child(label: "template", value: _template),
            Mirror.Child(label: "path", value: _path),
        ].filter {
            // Prefer attributes defined in a template if it clashes with predefined ones
            $0.label.map { label in
                !(InitCommand.requiredTemplateOptions.map(\.name) + InitCommand.optionalTemplateOptions.map(\.name))
                    .contains(label)
            } ?? true
        }
        return Mirror(InitCommand(), children: children + requiredTemplateChildren + optionalTemplateChildren)
    }
}
