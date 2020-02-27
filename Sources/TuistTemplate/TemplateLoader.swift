import Basic
import Foundation
import SPMUtility
import TuistSupport
import TemplateDescription
import TuistLoader

public protocol TemplateLoading {
    func templateDirectories() throws -> [AbsolutePath]
    func load(at path: AbsolutePath) throws -> TuistTemplate.Template
    func generate(at path: AbsolutePath,
                  to path: AbsolutePath,
                  attributes: [String]) throws
}

public class TemplateLoader: TemplateLoading {
    private let templatesDirectoryLocator: TemplatesDirectoryLocating
    private let resourceLocator: ResourceLocating
    private let templateDescriptionHelpersBuilder: TemplateDescriptionHelpersBuilding
    private let decoder: JSONDecoder

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
    }
    
    public func templateDirectories() throws -> [AbsolutePath] {
        let templatesDirectory = templatesDirectoryLocator.locate()
        let templates = try FileHandler.shared.contentsOfDirectory(templatesDirectory)
        let customTemplatesDirectory = templatesDirectoryLocator.locateCustom(at: FileHandler.shared.currentPath)
        let customTemplates = try customTemplatesDirectory.map(FileHandler.shared.contentsOfDirectory) ?? []
        return (templates + customTemplates).filter { $0.basename != Constants.templateHelpersDirectoryName }
    }
    
    public func load(at path: AbsolutePath) throws -> TuistTemplate.Template {
        let manifestPath = path.appending(component: "Template.swift")
        guard FileHandler.shared.exists(manifestPath) else {
            fatalError()
        }
        let data = try loadManifestData(at: manifestPath)
        let manifest = try decoder.decode(TemplateDescription.Template.self, from: data)
        return try TuistTemplate.Template.from(manifest: manifest,
                                               at: path)
    }
    
    public func generate(at sourcePath: AbsolutePath,
                         to destinationPath: AbsolutePath,
                         attributes: [String]) throws {
        let template = try load(at: sourcePath)
        
        let parsedAttributes = parseAttributes(attributes)
        let templateAttributes: [ParsedAttribute] = template.attributes.map {
            switch $0 {
            case let .optional(name, default: defaultValue):
                let value = parsedAttributes.first(where: { $0.name == name })?.value ?? defaultValue
                return ParsedAttribute(name: name, value: value)
            case let .required(name):
                guard let value = parsedAttributes.first(where: { $0.name == name })?.value else { fatalError() }
                return ParsedAttribute(name: name, value: value)
            }
        }
        
        let templateDescriptionPath = try resourceLocator.templateDescription()
        let jsonEncoder = JSONEncoder()
        
        let destinationDirectories = template.directories.map(destinationPath.appending)
        try parsedAttributes.reduce(destinationDirectories) { directories, attribute in
            directories.map {
                AbsolutePath($0.pathString.replacingOccurrences(of: "{{ \(attribute.name) }}", with: attribute.value))
            }
        }
        .forEach(FileHandler.shared.createFolder)
        try template.files.forEach {
            let destinationPath = destinationPath.appending($0.path)
            switch $0.contents {
            case let .static(contents):
                try generateFile(contents: contents,
                                 destinationPath: destinationPath,
                                 attributes: templateAttributes)
            case let .generated(generatePath):
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
                let templateDesciptionHelpersModulePath = try templateDescriptionHelpersBuilder.build(at: generatePath, templateDescriptionPath: templateDescriptionPath)
                if let templateDesciptionHelpersModulePath = templateDesciptionHelpersModulePath {
                    arguments.append(contentsOf: [
                        "-I", templateDesciptionHelpersModulePath.parentDirectory.pathString,
                        "-L", templateDesciptionHelpersModulePath.parentDirectory.pathString,
                        "-F", templateDesciptionHelpersModulePath.parentDirectory.pathString,
                        "-lTemplateDescriptionHelpers",
                    ])
                }
                
                arguments.append(generatePath.pathString)
                if let attributes = try String(data: jsonEncoder.encode(parsedAttributes), encoding: .utf8) {
                    arguments.append("--attributes")
                    arguments.append(attributes)
                }
                
                arguments.append("--tuist-dump")

                guard let result = try System.shared.capture(arguments).spm_chuzzle() else { fatalError() }
                try FileHandler.shared.write(result,
                                             path: destinationPath,
                                             atomically: true)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func loadManifestData(at path: AbsolutePath) throws -> Data {
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
        arguments.append("--tuist-dump")

        let result = try System.shared.capture(arguments).spm_chuzzle()
        guard let jsonString = result, let data = jsonString.data(using: .utf8) else {
            throw ManifestLoaderError.unexpectedOutput(path)
        }

        return data
    }

    private func generateFile(contents: String, destinationPath: AbsolutePath, attributes: [ParsedAttribute]) throws {
        let contentsWithFilledAttributes = attributes.reduce(contents) {
            $0.replacingOccurrences(of: "{{ \($1.name) }}", with: $1.value)
        }
        let finalDestinationPath = attributes.reduce(destinationPath) {
            AbsolutePath($0.pathString.replacingOccurrences(of: "{{ \($1.name) }}", with: $1.value))
        }
        try FileHandler.shared.write(contentsWithFilledAttributes,
                                     path: finalDestinationPath,
                                     atomically: true)
    }
    
    private func parseAttributes(_ attributes: [String]) -> [ParsedAttribute] {
        let (options, values): ([String], [String]) = attributes
            .reduce(([], [])) {
                $1.starts(with: "--") ? ($0.0 + [String($1.dropFirst(2))], $0.1) : ($0.0, $0.1 + [$1])
            }
        
        return zip(options, values).map(ParsedAttribute.init)
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
