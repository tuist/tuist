import Path
import TuistCore
import TuistLoader
import TuistScaffold
import TuistSupport
import XcodeGraph

enum InitServiceError: FatalError, Equatable {
    case ungettableProjectName(AbsolutePath)
    case nonEmptyDirectory(AbsolutePath)
    case templateNotFound(String)
    case templateNotProvided
    case attributeNotProvided(String)
    case invalidValue(argument: String, error: String)

    var type: ErrorType {
        switch self {
        case .ungettableProjectName, .nonEmptyDirectory, .templateNotFound, .templateNotProvided, .attributeNotProvided,
             .invalidValue:
            return .abort
        }
    }

    var description: String {
        switch self {
        case let .templateNotFound(template):
            return "Could not find template \(template). Make sure it exists at Tuist/Templates/\(template)"
        case .templateNotProvided:
            return "You must provide template name"
        case let .ungettableProjectName(path):
            return "Couldn't infer the project name from path \(path.pathString)."
        case let .nonEmptyDirectory(path):
            return "Can't initialize a project in the non-empty directory at path \(path.pathString)."
        case let .attributeNotProvided(name):
            return "You must provide \(name) option. Add --\(name) desired_value to your command."
        case let .invalidValue(argument: argument, error: error):
            return "\(error) for argument \(argument); use --help to print usage"
        }
    }
}

class InitService {
    private let templateLoader: TemplateLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateGenerator: TemplateGenerating
    private let templateGitLoader: TemplateGitLoading
    private let tuistVersionLoader: TuistVersionLoading

    init(
        templateLoader: TemplateLoading = TemplateLoader(),
        templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
        templateGenerator: TemplateGenerating = TemplateGenerator(),
        templateGitLoader: TemplateGitLoading = TemplateGitLoader(),
        tuistVersionLoader: TuistVersionLoading = TuistVersionLoader()
    ) {
        self.templateLoader = templateLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateGenerator = templateGenerator
        self.templateGitLoader = templateGitLoader
        self.tuistVersionLoader = tuistVersionLoader
    }

    func loadTemplateOptions(
        templateName: String,
        path: String?
    ) async throws -> (
        required: [String],
        optional: [String]
    ) {
        let path = try self.path(path)
        let directories = try templatesDirectoryLocator.templateDirectories(at: path)
        var attributes: [Template.Attribute] = []

        if templateName.isGitURL {
            try await templateGitLoader.loadTemplate(from: templateName) { template in
                attributes = template.attributes
            }
        } else {
            let templateDirectory = try templateDirectory(
                templateDirectories: directories,
                template: templateName
            )

            let template = try await templateLoader.loadTemplate(at: templateDirectory, plugins: .none)
            attributes = template.attributes
        }

        return attributes
            .reduce(into: (required: [], optional: [])) { currentValue, attribute in
                // name and platform attributes have default values, so add them to the optional
                if attribute.name == "name" || attribute.name == "platform" {
                    currentValue.optional.append(attribute.name)
                    return
                }
                switch attribute {
                case let .optional(name, default: _):
                    currentValue.optional.append(name)
                case let .required(name):
                    currentValue.required.append(name)
                }
            }
    }

    func run(
        name: String?,
        platform: String?,
        path: String?,
        templateName: String?,
        requiredTemplateOptions: [String: String],
        optionalTemplateOptions: [String: String?]
    ) async throws {
        let platform = try self.platform(platform)
        let path = try self.path(path)
        let name = try self.name(name, path: path)
        let templateName = templateName ?? "default"
        let tuistVersion = try tuistVersionLoader.getVersion()
        try verifyDirectoryIsEmpty(path: path)

        if templateName.isGitURL {
            try await templateGitLoader.loadTemplate(from: templateName, closure: { template in
                let parsedAttributes = try self.parseAttributes(
                    name: name,
                    platform: platform,
                    tuistVersion: tuistVersion,
                    requiredTemplateOptions: requiredTemplateOptions,
                    optionalTemplateOptions: optionalTemplateOptions,
                    template: template
                )

                try await self.templateGenerator.generate(
                    template: template,
                    to: path,
                    attributes: parsedAttributes
                )
            })
        } else {
            let directories = try templatesDirectoryLocator.templateDirectories(at: path)
            guard let templateDirectory = directories.first(where: { $0.basename == templateName })
            else { throw InitServiceError.templateNotFound(templateName) }

            let template = try await templateLoader.loadTemplate(at: templateDirectory, plugins: .none)
            let parsedAttributes = try parseAttributes(
                name: name,
                platform: platform,
                tuistVersion: tuistVersion,
                requiredTemplateOptions: requiredTemplateOptions,
                optionalTemplateOptions: optionalTemplateOptions,
                template: template
            )

            try await templateGenerator.generate(
                template: template,
                to: path,
                attributes: parsedAttributes
            )
        }

        logger.notice(
            "Project generated at path \(path.pathString). Run `tuist generate` to generate the project and open it in Xcode. Use `tuist edit` to easily update the Tuist project definition.",
            metadata: .success
        )
        logger
            .info(
                "To learn more about tuist features, such as how to add external dependencies or how to use our ProjectDescription helpers, head to our tutorials page: https://docs.tuist.io/tutorials/tuist-tutorials"
            )
    }

    // MARK: - Helpers

    /// Checks if the given directory is empty, essentially that it doesn't contain any file or directory.
    ///
    /// - Parameter path: Directory to be checked.
    /// - Throws: An InitServiceError.nonEmptyDirectory error when the directory is not empty.
    private func verifyDirectoryIsEmpty(path: AbsolutePath) throws {
        if !path.glob("*").isEmpty {
            throw InitServiceError.nonEmptyDirectory(path)
        }
    }

    /// Parses all `attributes` from `template`
    /// If those attributes are optional, they default to `default` if not provided
    /// - Returns: Array of parsed attributes
    private func parseAttributes(
        name: String,
        platform: Platform,
        tuistVersion: String,
        requiredTemplateOptions: [String: String],
        optionalTemplateOptions: [String: String?],
        template: Template
    ) throws -> [String: Template.Attribute.Value] {
        let defaultAttributes: [String: Template.Attribute.Value] = [
            "name": .string(name),
            "platform": .string(platform.caseValue),
            "tuist_version": .string(tuistVersion),
            "class_name": .string(name.toValidSwiftIdentifier()),
            "bundle_identifier": .string(name.toValidInBundleIdentifier()),
        ]
        return try template.attributes.reduce(into: defaultAttributes) { attributesDictionary, attribute in
            if defaultAttributes.keys.contains(attribute.name) { return }

            switch attribute {
            case let .required(name):
                guard let option = requiredTemplateOptions[name]
                else { throw ScaffoldServiceError.attributeNotProvided(name) }
                attributesDictionary[name] = .string(option)
            case let .optional(name, default: defaultValue):
                guard let unwrappedOption = optionalTemplateOptions[name],
                      let option = unwrappedOption
                else {
                    attributesDictionary[name] = defaultValue
                    return
                }
                attributesDictionary[name] = .string(option)
            }
        }
    }

    /// Finds template directory
    /// - Parameters:
    ///     - templateDirectories: Paths of available templates
    ///     - template: Name of template
    /// - Returns: `AbsolutePath` of template directory
    private func templateDirectory(templateDirectories: [AbsolutePath], template: String) throws -> AbsolutePath {
        guard let templateDirectory = templateDirectories.first(where: { $0.basename == template })
        else { throw InitServiceError.templateNotFound(template) }
        return templateDirectory
    }

    /// Returns name to use. If `name` is nil, returns a directory name executed `init` command.
    private func name(_ name: String?, path: AbsolutePath) throws -> String {
        if let name {
            return name
        } else if let directoryName = path.components.last {
            return directoryName
        } else {
            throw InitServiceError.ungettableProjectName(AbsolutePath.current)
        }
    }

    private func path(_ path: String?) throws -> AbsolutePath {
        if let path {
            return try AbsolutePath(validating: path, relativeTo: FileHandler.shared.currentPath)
        } else {
            return FileHandler.shared.currentPath
        }
    }

    private func platform(_ platform: String?) throws -> Platform {
        if let platformString = platform {
            if let platform = Platform(rawValue: platformString) {
                return platform
            } else {
                throw InitServiceError.invalidValue(argument: "platform", error: "Platform should be either ios, tvos, or macos")
            }
        } else {
            return .iOS
        }
    }
}
