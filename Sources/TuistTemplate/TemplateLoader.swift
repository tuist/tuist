import Basic
import Foundation
import SPMUtility
import TuistSupport
import TemplateDescription
import TuistLoader


public protocol TemplateLoading {
    /// - Returns: All available directories with defined templates (custom and built-in)
    func templateDirectories() throws -> [AbsolutePath]
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
    private let templateDescriptionHelpersBuilder: TemplateDescriptionHelpersBuilding
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Default constructor.
    public convenience init() {
        self.init(templatesDirectoryLocator: TemplatesDirectoryLocator(),
                  resourceLocator: ResourceLocator(),
                  templateDescriptionHelpersBuilder: TemplateDescriptionHelpersBuilder())
    }
    
    init(templatesDirectoryLocator: TemplatesDirectoryLocating,
         resourceLocator: ResourceLocating,
         templateDescriptionHelpersBuilder: TemplateDescriptionHelpersBuilding) {
        self.templatesDirectoryLocator = templatesDirectoryLocator
        self.resourceLocator = resourceLocator
        self.templateDescriptionHelpersBuilder = templateDescriptionHelpersBuilder
        decoder = JSONDecoder()
        encoder = JSONEncoder()
    }
    
    public func templateDirectories() throws -> [AbsolutePath] {
        let templatesDirectory = templatesDirectoryLocator.locate()
        let templates = try templatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        let customTemplatesDirectory = templatesDirectoryLocator.locateCustom(at: FileHandler.shared.currentPath)
        let customTemplates = try customTemplatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        return (templates + customTemplates).filter { $0.basename != Constants.templateHelpersDirectoryName }
    }
    
    public func loadTemplate(at path: AbsolutePath) throws -> TuistTemplate.Template {
        let manifestPath = path.appending(component: "Template.swift")
        guard FileHandler.shared.exists(manifestPath) else {
            fatalError()
        }
        let data = try loadManifestData(at: manifestPath)
        let manifest = try decoder.decode(TemplateDescription.Template.self, from: data)
        return try TuistTemplate.Template.from(manifest: manifest,
                                               at: path)
    }
    
    public func loadGenerateFile(at path: AbsolutePath, parsedAttributes: [TuistTemplate.ParsedAttribute]) throws -> String {
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
        let templateDescriptionPath = try resourceLocator.templateDescription()

        var arguments: [String] = [
            "/usr/bin/xcrun",
            "swiftc",
            "--driver-mode=swift",
            "-suppress-warnings",
            "-I", templateDescriptionPath.parentDirectory.pathString,
            "-L", templateDescriptionPath.parentDirectory.pathString,
            "-F", templateDescriptionPath.parentDirectory.pathString,
            "-lTemplateDescription",
        ]
        
        // Helpers
        let templateDesciptionHelpersModulePath = try templateDescriptionHelpersBuilder.build(at: path, templateDescriptionPath: templateDescriptionPath)
        if let templateDesciptionHelpersModulePath = templateDesciptionHelpersModulePath {
            arguments.append(contentsOf: [
                "-I", templateDesciptionHelpersModulePath.parentDirectory.pathString,
                "-L", templateDesciptionHelpersModulePath.parentDirectory.pathString,
                "-F", templateDesciptionHelpersModulePath.parentDirectory.pathString,
                "-lTemplateDescriptionHelpers",
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
    static func from(manifest: TemplateDescription.Template, at path: AbsolutePath) throws -> TuistTemplate.Template {
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
    static func from(manifest: TemplateDescription.Template.Attribute) throws -> TuistTemplate.Template.Attribute {
        switch manifest {
        case let .required(name):
            return .required(name)
        case let .optional(name, default: defaultValue):
            return .optional(name, default: defaultValue)
        }
    }
}

extension TuistTemplate.Template.Contents {
    static func from(manifest: TemplateDescription.Template.Contents,
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
    static func from(manifest: TemplateDescription.ParsedAttribute) throws -> TuistTemplate.ParsedAttribute {
        TuistTemplate.ParsedAttribute(name: manifest.name,
                                      value: manifest.value)
    }
}
