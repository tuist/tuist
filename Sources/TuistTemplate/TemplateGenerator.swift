import Basic
import Foundation
import TuistSupport
import TuistLoader

public protocol TemplateGenerating {
    /// Generate files for template manifest at `path`
    /// - Parameters:
    ///     - at: Path of directory where `Template.swift` is located
    ///     - to: Path of directory where files should be generated to
    ///     - attributes: Attributes from user input
    func generate(at path: AbsolutePath,
                  to path: AbsolutePath,
                  attributes: [String]) throws
}

public final class TemplateGenerator: TemplateGenerating {
    private let templateLoader: TemplateLoading
    private let templateDescriptionHelpersBuilder: TemplateDescriptionHelpersBuilding
    
    public init(templateLoader: TemplateLoading = TemplateLoader(),
                templateDescriptionHelpersBuilder: TemplateDescriptionHelpersBuilding = TemplateDescriptionHelpersBuilder()) {
        self.templateLoader = templateLoader
        self.templateDescriptionHelpersBuilder = templateDescriptionHelpersBuilder
    }
    
    public func generate(at sourcePath: AbsolutePath,
                  to destinationPath: AbsolutePath,
                  attributes: [String]) throws {
        let template = try templateLoader.loadTemplate(at: sourcePath)
        
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
                let content = try templateLoader.loadGenerateFile(at: generatePath, parsedAttributes: templateAttributes)
                try FileHandler.shared.write(content,
                                             path: destinationPath,
                                             atomically: true)
            }
        }
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
