import Basic
import Foundation
import SPMUtility
import TuistSupport
import ProjectDescription
import TuistLoader

public enum TemplateLoaderError: FatalError, Equatable {
    public var type: ErrorType { .abort }
    
    case manifestNotFound(AbsolutePath)
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
    /// Load `TuistTemplate.Template` at given `path`
    /// - Parameters:
    ///     - path: Path of template manifest file `Template.swift`
    /// - Returns: Loaded `TuistTemplate.Template`
    func loadTemplate(at path: AbsolutePath) throws -> TuistTemplate.Template
    /// Loads and renders content in generate file
    /// - Parameters:
    ///     - path: Path of generate file
    ///     - parsedAttributes: Array of `ParsedAttribute` from user input
    /// - Returns: Rendered generate file
    func loadGenerateFile(at path: AbsolutePath, parsedAttributes: [TuistTemplate.ParsedAttribute]) throws -> String
}

public class TemplateLoader: TemplateLoading {
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let resourceLocator: ResourceLocating
    private let projectDescriptionHelpersBuilder: ProjectDescriptionHelpersBuilding
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

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
        encoder = JSONEncoder()
    }
    
    public func loadTemplate(at path: AbsolutePath) throws -> TuistTemplate.Template {
        let manifestPath = path.appending(component: "Template.swift")
        guard FileHandler.shared.exists(manifestPath) else {
            throw TemplateLoaderError.manifestNotFound(manifestPath)
        }
        let data = try loadManifestData(at: manifestPath)
        let manifest = try decoder.decode(ProjectDescription.Template.self, from: data)
        return try TuistTemplate.Template.from(manifest: manifest,
                                               at: path)
    }
    
    public func loadGenerateFile(at path: AbsolutePath, parsedAttributes: [TuistTemplate.ParsedAttribute]) throws -> String {
        guard FileHandler.shared.exists(path) else {
            throw TemplateLoaderError.generateFileNotFound(path)
        }
        var additionalArguments: [String] = []
        if let attributes = try String(data: encoder.encode(parsedAttributes), encoding: .utf8) {
            additionalArguments.append("--attributes")
            additionalArguments.append(attributes)
        }
        let data = try loadManifestData(at: path, additionalArguments: additionalArguments)
        return try decoder.decode(String.self, from: data)
    }
    
    // MARK: - Helpers
    
    private func loadManifestData(at path: AbsolutePath, additionalArguments: [String] = []) throws -> Data {
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
        arguments.append(contentsOf: additionalArguments)
        arguments.append("--tuist-dump")

        let result = try System.shared.capture(arguments).spm_chuzzle()
        guard let jsonString = result, let data = jsonString.data(using: .utf8) else {
            throw ManifestLoaderError.unexpectedOutput(path)
        }

        return data
    }
}

extension TuistTemplate.Template {
    static func from(manifest: ProjectDescription.Template, at path: AbsolutePath) throws -> TuistTemplate.Template {
        let attributes = try manifest.attributes.map(TuistTemplate.Template.Attribute.from)
        let files = try manifest.files.map { (path: RelativePath($0.path),
                                              contents: try TuistTemplate.Template.Contents.from(manifest: $0.contents,
                                                                                                 at: path)) }
        let directories = manifest.directories.map { RelativePath($0) }
        return TuistTemplate.Template(description: manifest.description,
                                      attributes: attributes,
                                      files: files,
                                      directories: directories)
    }
}

extension TuistTemplate.Template.Attribute {
    static func from(manifest: ProjectDescription.Template.Attribute) throws -> TuistTemplate.Template.Attribute {
        switch manifest {
        case let .required(name):
            return .required(name)
        case let .optional(name, default: defaultValue):
            return .optional(name, default: defaultValue)
        }
    }
}

extension TuistTemplate.Template.Contents {
    static func from(manifest: ProjectDescription.Template.Contents,
                     at path: AbsolutePath) throws -> TuistTemplate.Template.Contents {
        switch manifest {
        case let .static(contents):
            return .static(contents)
        case let .generated(generatePath):
            return .generated(path.appending(component: generatePath))
        }
    }
}

extension TuistTemplate.ParsedAttribute {
    static func from(manifest: ProjectDescription.ParsedAttribute) throws -> TuistTemplate.ParsedAttribute {
        TuistTemplate.ParsedAttribute(name: manifest.name,
                                      value: manifest.value)
    }
}
