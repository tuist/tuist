import Basic
import Foundation
import ProjectDescription
import SPMUtility
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
        return try TuistCore.Template.from(manifest: template,
                                           at: path)
    }
}

extension TuistCore.Template {
    static func from(manifest: ProjectDescription.Template, at path: AbsolutePath) throws -> TuistCore.Template {
        let attributes = try manifest.attributes.map(TuistCore.Template.Attribute.from)
        let files = try manifest.files.map { (path: RelativePath($0.path),
                                              contents: try TuistCore.Template.Contents.from(manifest: $0.contents,
                                                                                                 at: path)) }
        let directories = manifest.directories.map { RelativePath($0) }
        return TuistCore.Template(description: manifest.description,
                                      attributes: attributes,
                                      files: files,
                                      directories: directories)
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
                     at path: AbsolutePath) throws -> TuistCore.Template.Contents {
        switch manifest {
        case let .string(contents):
            return .string(contents)
        case let .file(generatePath):
            return .file(path.appending(component: generatePath))
        }
    }
}
