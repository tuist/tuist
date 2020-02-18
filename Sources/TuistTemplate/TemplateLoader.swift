import Basic
import Foundation
import SPMUtility
import TuistSupport
import TuistLoader
import ProjectDescription

public protocol TemplateLoading {
    func templateDirectories() throws -> [AbsolutePath]
    func load(at path: AbsolutePath) throws -> TuistLoader.Template
    func generate(at path: AbsolutePath,
                  to path: AbsolutePath,
                  attributes: [String]) throws
}

public class TemplateLoader: TemplateLoading {
    /// Manifest loader instance to load the setup.
    private let manifestLoader: ManifestLoading
    
    private let templatesDirectoryLocator: TemplatesDirectoryLocating

    /// Default constructor.
    public convenience init() {
        self.init(manifestLoader: ManifestLoader(),
                  templatesDirectoryLocator: TemplatesDirectoryLocator())
    }
    
    init(manifestLoader: ManifestLoading, templatesDirectoryLocator: TemplatesDirectoryLocating) {
        self.manifestLoader = manifestLoader
        self.templatesDirectoryLocator = templatesDirectoryLocator
    }
    
    public func templateDirectories() throws -> [AbsolutePath] {
        let templatesDirectory = templatesDirectoryLocator.locate()
        let templates = try templatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        let customTemplatesDirectory = templatesDirectoryLocator.locateCustom(at: FileHandler.shared.currentPath)
        let customTemplates = try customTemplatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        return templates + customTemplates
    }
    
    public func load(at path: AbsolutePath) throws -> TuistLoader.Template {
        let manifest = try manifestLoader.loadTemplate(at: path)
        return try TuistLoader.Template.from(manifest: manifest)
    }
    
    typealias ParsedAttribute = (name: String, value: String)
    
    public func generate(at sourcePath: AbsolutePath,
                         to destinationPath: AbsolutePath,
                         attributes: [String]) throws {
        let template = try load(at: sourcePath)
        
        let parsedAttributes = parseAttributes(attributes)
        let templateAttributes: [ParsedAttribute] = template.attributes.map {
            switch $0 {
            case let .optional(name, default: defaultValue):
                let value = parsedAttributes.first(where: { $0.name == name })?.value ?? defaultValue
                return (name: name, value: value)
            case let .required(name):
                guard let value = parsedAttributes.first(where: { $0.name == name })?.value else { fatalError() }
                return (name: name, value: value)
            }
        }
        
        try template.directories.map(destinationPath.appending).forEach(FileHandler.shared.createFolder)
        try template.files.forEach {
            try generateFile(contents: $0.contents,
                             destinationPath: destinationPath.appending($0.path),
                             attributes: templateAttributes)
        }
    }
    
    // MARK: - Helpers

    private func generateFile(contents: String, destinationPath: AbsolutePath, attributes: [ParsedAttribute]) throws {
        let contentsWithFilledAttributes = attributes.reduce(contents) {
            $0.replacingOccurrences(of: "{{ \($1.name) }}", with: $1.value)
        }
        try FileHandler.shared.write(contentsWithFilledAttributes,
                                     path: destinationPath,
                                     atomically: true)
    }
    
    private func parseAttributes(_ attributes: [String]) -> [(name: String, value: String)] {
        attributes.map {
            let splitAttributes = $0.components(separatedBy: "=")
            // TODO: Error with proper format
            guard splitAttributes.count == 2 else { fatalError() }
            let name = splitAttributes[0]
            let value = splitAttributes[1]
            return (name: name, value: value)
        }
    }
}

extension TuistLoader.Template {
    static func from(manifest: ProjectDescription.Template) throws -> TuistLoader.Template {
        let attributes = try manifest.attributes.map(TuistLoader.Template.Attribute.from)
        let files = manifest.files.map { (path: RelativePath($0.path), contents: $0.contents) }
        let directories = manifest.directories.map { RelativePath($0) }
        return TuistLoader.Template(description: manifest.description,
                                    attributes: attributes,
                                    files: files,
                                    directories: directories)
    }
}

extension TuistLoader.Template.Attribute {
    static func from(manifest: ProjectDescription.Template.Attribute) throws -> TuistLoader.Template.Attribute {
        switch manifest {
        case let .required(name):
            return .required(name)
        case let .optional(name, default: defaultValue):
            return .optional(name, default: defaultValue)
        }
    }
}
