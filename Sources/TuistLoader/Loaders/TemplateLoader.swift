import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

public protocol TemplateLoading {
    /// Load `TuistScaffold.Template` at given `path`
    /// - Parameters:
    ///     - path: Path of template manifest file `Template.swift`
    /// - Returns: Loaded `TuistScaffold.Template`
    func loadTemplate(at path: AbsolutePath) throws -> TuistCore.Template
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

    public func loadTemplate(at path: AbsolutePath) throws -> TuistCore.Template {
        let template = try manifestLoader.loadTemplate(at: path)
        let generatorPaths = GeneratorPaths(manifestDirectory: path)
        return try TuistCore.Template.from(manifest: template,
                                           generatorPaths: generatorPaths)
    }
}

extension TuistCore.Template {
    static func from(manifest: ProjectDescription.Template, generatorPaths: GeneratorPaths) throws -> TuistCore.Template {
        let attributes = try manifest.attributes.map(TuistCore.Template.Attribute.from)
        let files = try manifest.files.map { File(path: RelativePath($0.path),
                                                  contents: try TuistCore.Template.Contents.from(manifest: $0.contents,
                                                                                                 generatorPaths: generatorPaths)) }
        return TuistCore.Template(description: manifest.description,
                                  attributes: attributes,
                                  files: files)
    }
}

extension TuistCore.Template.Attribute {
    static func from(manifest: ProjectDescription.Template.Attribute) throws -> TuistCore.Template.Attribute {
        switch manifest {
        case let .required(name):
            return .required(name)
        case let .optional(name, default: defaultValue):
            return .optional(name, default: defaultValue)
        }
    }
}

extension TuistCore.Template.Contents {
    static func from(manifest: ProjectDescription.Template.Contents,
                     generatorPaths: GeneratorPaths) throws -> TuistCore.Template.Contents
    {
        switch manifest {
        case let .string(contents):
            return .string(contents)
        case let .file(templatePath):
            return .file(try generatorPaths.resolve(path: templatePath))
        }
    }
}
