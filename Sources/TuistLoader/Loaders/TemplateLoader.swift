import Basic
import Foundation
import SPMUtility
import TuistSupport
import ProjectDescription

public protocol TemplateLoading {
    func load(at path: AbsolutePath) throws -> Template
    func generate(at path: AbsolutePath, to path: AbsolutePath) throws
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
    
    public func generate(at sourcePath: AbsolutePath,
                         to destinationPath: AbsolutePath) throws {
        let template = try load(at: sourcePath)
        try template.directories.map(destinationPath.appending).forEach(FileHandler.shared.createFolder)
        try template.files.forEach { try FileHandler.shared.write($0.contents,
                                                                  path: destinationPath.appending($0.path),
                                                                  atomically: true) }
    }
}

extension TuistLoader.Template {
    static func from(manifest: ProjectDescription.Template) throws -> TuistLoader.Template {
        let files = manifest.files.map { (path: RelativePath($0.path), contents: $0.contents) }
        let directories = manifest.directories.map { RelativePath($0) }
        return TuistLoader.Template(description: manifest.description,
                                    files: files,
                                    directories: directories)
    }
}
