import Basic
import Foundation
import SPMUtility
import TuistSupport

public protocol TemplateLoading {
    func generate(at path: AbsolutePath) throws
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
    
    public func generate(at path: AbsolutePath) throws {
        let template = try manifestLoader.loadTemplate(at: path)
        
    }
}
