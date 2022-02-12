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
    /// - Returns: Loaded `TuistScaffold.Template`
    func loadTemplate(at path: AbsolutePath) throws -> TuistGraph.Template
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

    public func loadTemplate(at path: AbsolutePath) throws -> TuistGraph.Template {
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
            path: RelativePath($0.path),
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
            return .optional(name, default: defaultValue)
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
