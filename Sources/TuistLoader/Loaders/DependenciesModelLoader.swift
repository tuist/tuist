import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

/// Entity responsible for providing dependencies models
public protocol DependenciesModelLoading {
    /// Load array of Carthage Dependency models at the specified path.
    /// - Parameter path: The absolute path for the dependency models to load.
    /// - Returns: The array of Carthage Dependency models from the specified path.
    /// - Throws: Error encountered during the loading process (e.g. Missing Dependencies file).
    func loadDependencies(at path: AbsolutePath) throws -> [CarthageDependency]
}

public class DependenciesModelLoader: DependenciesModelLoading {
    private let manifestLoader: ManifestLoading
    
    public init(manifestLoader: ManifestLoading = ManifestLoader()) {
        self.manifestLoader = manifestLoader
    }
    
    public func loadDependencies(at path: AbsolutePath) throws -> [CarthageDependency] {
        let dependenciesManifest = try manifestLoader.loadDependencies(at: path).dependencies
        let carthageDependenciesManifest = dependenciesManifest
            .filter { $0.manager == .carthage }
        
        return carthageDependenciesManifest
            .map { CarthageDependency.from(manifest: $0) }
    }
}
