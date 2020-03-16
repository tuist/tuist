import Basic
import Foundation
import ProjectDescription
import SPMUtility
import TuistLoader
import TuistSupport

public enum TemplateLoaderError: FatalError, Equatable {
    public var type: ErrorType { .abort }

    /// Template manifest was not found
    case manifestNotFound(AbsolutePath)
    /// Could not find file for generating content
    case generateFileNotFound(AbsolutePath)

    public var description: String {
        switch self {
        case let .manifestNotFound(manifestPath):
            return "Could not find template manifest at \(manifestPath.pathString)"
        case let .generateFileNotFound(generateFilePath):
            return "Could not find generate file at \(generateFilePath.pathString)"
        }
    }
}

public protocol TemplateLoading {
    /// Load `TuistScaffold.Template` at given `path`
    /// - Parameters:
    ///     - path: Path of template manifest file `Template.swift`
    /// - Returns: Loaded `TuistScaffold.Template`
    func loadTemplate(at path: AbsolutePath) throws -> TuistScaffold.Template
}

public class TemplateLoader: TemplateLoading {
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let resourceLocator: ResourceLocating
    private let projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding
    private let decoder: JSONDecoder

    /// Default constructor.
    public convenience init() {
        self.init(templatesDirectoryLocator: TemplatesDirectoryLocator(),
                  resourceLocator: ResourceLocator(),
                  projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilder())
    }

    init(templatesDirectoryLocator: TemplatesDirectoryLocating,
         resourceLocator: ResourceLocating,
         projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding) {
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.resourceLocator = resourceLocator
        self.projectDescriptionHelpersBuilder = projectDescriptionHelpersBuilder
        decoder = JSONDecoder()
    }

    public func loadTemplate(at path: AbsolutePath) throws -> TuistScaffold.Template {
        let manifestPath = path.appending(component: "Template.swift")
        guard FileHandler.shared.exists(manifestPath) else {
            throw TemplateLoaderError.manifestNotFound(manifestPath)
        }
        let data = try loadManifestData(at: manifestPath)
        let manifest = try decoder.decode(ProjectDescription.Template.self, from: data)
        return try TuistScaffold.Template.from(manifest: manifest,
                                               at: path)
    }

    // MARK: - Helpers

    private func loadManifestData(at path: AbsolutePath) throws -> Data {
        let projectDescriptionPath = try resourceLocator.projectDescription()

        var arguments: [String] = [
            "/usr/bin/xcrun",
            "swiftc",
            "--driver-mode=swift",
            "-suppress-warnings",
            "-I", projectDescriptionPath.parentDirectory.pathString,
            "-L", projectDescriptionPath.parentDirectory.pathString,
            "-F", projectDescriptionPath.parentDirectory.pathString,
            "-lProjectDescription",
        ]

        // Helpers
        let projectDesciptionHelpersModulePath = try projectDescriptionHelpersBuilder.build(at: path, projectDescriptionPath: projectDescriptionPath)
        if let projectDesciptionHelpersModulePath = projectDesciptionHelpersModulePath {
            arguments.append(contentsOf: [
                "-I", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-L", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-F", projectDesciptionHelpersModulePath.parentDirectory.pathString,
                "-lProjectDescriptionHelpers",
            ])
        }

        arguments.append(path.pathString)
        arguments.append("--tuist-dump")

        let result = try System.shared.capture(arguments).spm_chuzzle()
        guard let jsonString = result, let data = jsonString.data(using: .utf8) else {
            throw ManifestLoaderError.unexpectedOutput(path)
        }

        return data
    }
}

extension TuistScaffold.Template {
    static func from(manifest: ProjectDescription.Template, at path: AbsolutePath) throws -> TuistScaffold.Template {
        let attributes = try manifest.attributes.map(TuistScaffold.Template.Attribute.from)
        let files = try manifest.files.map { (path: RelativePath($0.path),
                                              contents: try TuistScaffold.Template.Contents.from(manifest: $0.contents,
                                                                                                 at: path)) }
        let directories = manifest.directories.map { RelativePath($0) }
        return TuistScaffold.Template(description: manifest.description,
                                      attributes: attributes,
                                      files: files,
                                      directories: directories)
    }
}

extension TuistScaffold.Template.Attribute {
    static func from(manifest: ProjectDescription.Template.Attribute) throws -> TuistScaffold.Template.Attribute {
        switch manifest {
        case let .required(name):
            return .required(name)
        case let .optional(name, default: defaultValue):
            return .optional(name, default: defaultValue)
        }
    }
}

extension TuistScaffold.Template.Contents {
    static func from(manifest: ProjectDescription.Template.Contents,
                     at path: AbsolutePath) throws -> TuistScaffold.Template.Contents {
        switch manifest {
        case let .string(contents):
            return .string(contents)
        case let .file(generatePath):
            return .file(path.appending(component: generatePath))
        }
    }
}
