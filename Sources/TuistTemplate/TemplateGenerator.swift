import Basic
import Foundation
import TuistLoader
import TuistSupport

enum TemplateGeneratorError: FatalError, Equatable {
    var type: ErrorType { .abort }

    case attributeNotFound(String)

    var description: String {
        switch self {
        case let .attributeNotFound(attribute):
            return "You must provide \(attribute) attribute"
        }
    }
}

/// Interface for generating content defined in template manifest
public protocol TemplateGenerating {
    /// Generate files for template manifest at `path`
    /// - Parameters:
    ///     - sourcePath: Path of directory where `Template.swift` is located
    ///     - destinationPath: Path of directory where files should be generated to
    ///     - attributes: Attributes from user input
    func generate(at sourcePath: AbsolutePath,
                  to destinationPath: AbsolutePath,
                  attributes: [String]) throws
}

public final class TemplateGenerator: TemplateGenerating {
    private let templateLoader: TemplateLoading

    public init(templateLoader: TemplateLoading = TemplateLoader()) {
        self.templateLoader = templateLoader
    }

    public func generate(at sourcePath: AbsolutePath,
                         to destinationPath: AbsolutePath,
                         attributes: [String]) throws {
        let template = try templateLoader.loadTemplate(at: sourcePath)
        let templateAttributes = try getTemplateAttributes(with: attributes, template: template)

        try generateDirectories(template: template,
                                templateAttributes: templateAttributes,
                                destinationPath: destinationPath)

        try generateFiles(template: template,
                          templateAttributes: templateAttributes,
                          destinationPath: destinationPath)
    }

    // MARK: - Helpers

    private func generateDirectories(template: Template,
                                     templateAttributes: [ParsedAttribute],
                                     destinationPath: AbsolutePath) throws {
        let destinationDirectories = template.directories.map(destinationPath.appending)
        try templateAttributes.reduce(destinationDirectories) { directories, attribute in
            directories.map {
                AbsolutePath($0.pathString.replacingOccurrences(of: "{{ \(attribute.name) }}", with: attribute.value))
            }
        }
        .forEach(FileHandler.shared.createFolder)
    }

    private func generateFiles(template: Template,
                               templateAttributes: [ParsedAttribute],
                               destinationPath: AbsolutePath) throws {
        try template.files.forEach {
            let destinationPath = templateAttributes.reduce(destinationPath.appending($0.path)) {
                AbsolutePath($0.pathString.replacingOccurrences(of: "{{ \($1.name) }}", with: $1.value))
            }
            switch $0.contents {
            case let .static(contents):
                try generateFile(contents: contents,
                                 destinationPath: destinationPath,
                                 attributes: templateAttributes)
            case let .generated(generatePath):
                print(generatePath)
                let content = try templateLoader.loadGenerateFile(at: generatePath, parsedAttributes: templateAttributes)
                try FileHandler.shared.write(content,
                                             path: destinationPath,
                                             atomically: true)
            }
        }
    }

    private func getTemplateAttributes(with attributes: [String], template: Template) throws -> [ParsedAttribute] {
        let parsedAttributes = parseAttributes(attributes)
        return try template.attributes.map {
            switch $0 {
            case let .optional(name, default: defaultValue):
                let value = parsedAttributes.first(where: { $0.name == name })?.value ?? defaultValue
                return ParsedAttribute(name: name, value: value)
            case let .required(name):
                guard
                    let value = parsedAttributes.first(where: { $0.name == name })?.value
                else { throw TemplateGeneratorError.attributeNotFound(name) }
                return ParsedAttribute(name: name, value: value)
            }
        }
    }

    private func generateFile(contents: String,
                              destinationPath: AbsolutePath,
                              attributes: [ParsedAttribute]) throws {
        let contentsWithFilledAttributes = attributes.reduce(contents) {
            $0.replacingOccurrences(of: "{{ \($1.name) }}", with: $1.value)
        }
        try FileHandler.shared.write(contentsWithFilledAttributes,
                                     path: destinationPath,
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
