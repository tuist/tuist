import Basic
import Foundation
import SPMUtility
import TuistSupport
import ProjectDescription

public protocol TemplateLoading {
    func load(at path: AbsolutePath) throws -> Template
}

public class TemplateLoader: TemplateLoading {
    /// Manifset loader instance to load the setup.
    private let manifestLoader: ManifestLoading

    /// Default constructor.
    public convenience init() {
        let manifestLoader = ManifestLoader()
        self.init(manifestLoader: manifestLoader)
    }
    
    init(manifestLoader: ManifestLoading) {
        self.manifestLoader = manifestLoader
    }
    
    public func load(at path: AbsolutePath) throws -> Template {
        let manifest = try manifestLoader.loadTemplate(at: path)
        return try TuistLoader.Template.from(manifest: manifest)
    }
}

extension TuistLoader.Template {
    static func from(manifest: ProjectDescription.Template) throws -> TuistLoader.Template {
        return TuistLoader.Template(description: manifest.description)
    }
}
