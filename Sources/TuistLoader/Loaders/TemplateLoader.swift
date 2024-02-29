import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

public protocol TemplateLoading {
    /// Load `TuistScaffold.Template` at given `path`
    /// - Parameters:
    ///     - path: Path of template manifest file `name_of_template.swift`
    ///     - plugins: List of available plugins.
    /// - Returns: Loaded `TuistScaffold.Template`
    func loadTemplate(at path: AbsolutePath, plugins: Plugins) throws -> TuistGraph.Template
}

extension TemplateLoading {
    public func loadTemplate(at path: AbsolutePath) throws -> TuistGraph.Template {
        try loadTemplate(at: path, plugins: .none)
    }
}

public class TemplateLoader: TemplateLoading {
    private let manifestLoader: ManifestLoading

    /// Default constructor.
    public convenience init() {
        self.init(manifestLoader: ManifestLoader())
    }

    init(manifestLoader: ManifestLoading) {
        self.manifestLoader = manifestLoader
    }

    public func loadTemplate(at path: AbsolutePath, plugins: Plugins) throws -> TuistGraph.Template {
        try manifestLoader.register(plugins: plugins)
        let template = try manifestLoader.loadTemplate(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        return try TuistGraph.Template.from(
            manifest: template,
            generatorPaths: generatorPaths
        )
    }
}

extension TuistGraph.Template {
    static func from(manifest: ProjectDescription.Template, generatorPaths: GeneratorPaths) throws -> TuistGraph.Template {
        let attributes = try manifest.attributes.map(TuistGraph.Template.Attribute.from)
        let items = try manifest.items.map { Item(
            path: try RelativePath(validating: $0.path),
            contents: try TuistGraph.Template.Contents.from(
                manifest: $0.contents,
                generatorPaths: generatorPaths
            )
        ) }
        return TuistGraph.Template(
            description: manifest.description,
            attributes: attributes,
            items: items
        )
    }
}

extension TuistGraph.Template.Attribute {
    static func from(manifest: ProjectDescription.Template.Attribute) throws -> TuistGraph.Template.Attribute {
        switch manifest {
        case let .required(name):
            return .required(name)
        case let .optional(name, default: defaultValue):
            return .optional(name, default: try Self.Value.from(value: defaultValue))
        }
    }
}

extension TuistGraph.Template.Attribute.Value {
    static func from(value: ProjectDescription.Template.Attribute.Value) throws -> TuistGraph.Template.Attribute.Value {
        switch value {
        case let .string(string):
            return .string(string)
        case let .integer(integer):
            return .integer(integer)
        case let .real(real):
            return .real(real)
        case let .boolean(boolean):
            return .boolean(boolean)
        case let .dictionary(dictionary):
            var newDictionary: [String: TuistGraph.Template.Attribute.Value] = [:]
            for (key, value) in dictionary {
                newDictionary[key] = try from(value: value)
            }
            return .dictionary(newDictionary)
        case let .array(array):
            let newArray: [TuistGraph.Template.Attribute.Value] = try array.map { try from(value: $0) }
            return .array(newArray)
        }
    }
}

extension TuistGraph.Template.Contents {
    static func from(
        manifest: ProjectDescription.Template.Contents,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.Template.Contents {
        switch manifest {
        case let .string(contents):
            return .string(contents)
        case let .file(templatePath):
            return .file(try generatorPaths.resolve(path: templatePath))
        case let .directory(sourcePath):
            return .directory(try generatorPaths.resolve(path: sourcePath))
        }
    }
}
