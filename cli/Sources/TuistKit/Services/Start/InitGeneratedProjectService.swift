import FileSystem
import Foundation
import Mockable
import Path
import TuistCore
import TuistLoader
import TuistScaffold
import TuistSupport
import XcodeGraph

enum InitGeneratedProjectServiceError: LocalizedError, Equatable {
    case ungettableProjectName(AbsolutePath)
    case nonEmptyDirectory(AbsolutePath)
    case templateNotFound(String)
    case invalidValue(argument: String, error: String)

    var errorDescription: String? {
        switch self {
        case let .templateNotFound(template):
            return "Could not find template \(template). Make sure it exists at Tuist/Templates/\(template)"
        case let .ungettableProjectName(path):
            return "Couldn't infer the project name from path \(path.pathString)."
        case let .nonEmptyDirectory(path):
            return "Can't initialize a project in the non-empty directory at path \(path.pathString)."
        case let .invalidValue(argument: argument, error: error):
            return "\(error) for argument \(argument); use --help to print usage"
        }
    }
}

@Mockable
protocol InitGeneratedProjectServicing {
    func run(
        name: String?,
        platform: String?,
        path: String?
    ) async throws
}

class InitGeneratedProjectService: InitGeneratedProjectServicing {
    private let templateLoader: TemplateLoading
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let templateGenerator: TemplateGenerating
    private let templateGitLoader: TemplateGitLoading
    private let fileSystem: FileSysteming

    init(
        templateLoader: TemplateLoading = TemplateLoader(),
        templatesDirectoryLocator: TemplatesDirectoryLocating = TemplatesDirectoryLocator(),
        templateGenerator: TemplateGenerating = TemplateGenerator(),
        templateGitLoader: TemplateGitLoading = TemplateGitLoader(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.templateLoader = templateLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.templateGenerator = templateGenerator
        self.templateGitLoader = templateGitLoader
        self.fileSystem = fileSystem
    }

    func run(
        name: String?,
        platform: String?,
        path: String?
    ) async throws {
        let platform = try self.platform(platform)
        let path = try self.path(path)
        let name = try self.name(name, path: path)
        let templateName = "default"
        let directories = try await templatesDirectoryLocator.templateDirectories(at: path)
        guard let templateDirectory = directories.first(where: { $0.basename == templateName })
        else { throw InitGeneratedProjectServiceError.templateNotFound(templateName) }

        let template = try await templateLoader.loadTemplate(at: templateDirectory, plugins: .none)
        let parsedAttributes: [String: Template.Attribute.Value] = [
            "name": .string(name),
            "platform": .string(platform.caseValue),
            "tuist_version": .string(Constants.version),
            "class_name": .string(name.toValidSwiftIdentifier()),
            "bundle_identifier": .string(name.toValidInBundleIdentifier()),
        ]

        try await templateGenerator.generate(
            template: template,
            to: path,
            attributes: parsedAttributes
        )
    }

    // MARK: - Helpers

    /// Finds template directory
    /// - Parameters:
    ///     - templateDirectories: Paths of available templates
    ///     - template: Name of template
    /// - Returns: `AbsolutePath` of template directory
    private func templateDirectory(templateDirectories: [AbsolutePath], template: String) throws -> AbsolutePath {
        guard let templateDirectory = templateDirectories.first(where: { $0.basename == template })
        else { throw InitGeneratedProjectServiceError.templateNotFound(template) }
        return templateDirectory
    }

    /// Returns name to use. If `name` is nil, returns the name of the directory `init` was executed in.
    private func name(_ name: String?, path: AbsolutePath) throws -> String {
        if let name {
            return name
        } else if let directoryName = path.components.last {
            return directoryName
        } else {
            throw InitGeneratedProjectServiceError.ungettableProjectName(AbsolutePath.current)
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
                throw InitGeneratedProjectServiceError.invalidValue(
                    argument: "platform",
                    error: "Platform should be either ios, tvos, watchos, or macos"
                )
            }
        } else {
            return .iOS
        }
    }
}
