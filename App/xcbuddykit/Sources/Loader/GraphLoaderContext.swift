import Basic
import Foundation

/// Protocol that defines the interface of the context that is used during the graph loading.
protocol GraphLoaderContexting: AnyObject {
    /// Manifest loader that is used to get a JSON representation of the manifests.
    var manifestLoader: GraphManifestLoading { get }

    /// Contains a reference to the manifests that are parsed during the graph loading.
    var cache: GraphLoaderCaching { get }

    /// Util to handle files.
    var fileHandler: FileHandling { get }

    /// Circular dependency detector.
    var circularDetector: GraphCircularDetecting { get }

    /// Shell.
    var shell: Shelling { get }
}

/// Object passed during the graph loading that contains utils to be used.
class GraphLoaderContext: GraphLoaderContexting {
    /// Manifest loader. It's used to get a JSON representation of the manifests.
    let manifestLoader: GraphManifestLoading

    /// Contains a reference to the manifests that are parsed during the graph loading.
    let cache: GraphLoaderCaching

    /// Util to handle files.
    let fileHandler: FileHandling

    /// Circular dependency detector.
    let circularDetector: GraphCircularDetecting

    /// Shell.
    let shell: Shelling

    /// Initializes the context with its attributes.
    ///
    /// - Parameters:
    ///   - manifestLoader: Manifest loader that is used to get a JSON representation of the manifests.
    ///   - cache: Contains a reference to the manifests that are parsed during the graph loading.
    ///   - fileHandler: Util to handle files.
    ///   - circularDetector: Circular dependency detector.
    ///   - shell: shell.
    init(manifestLoader: GraphManifestLoading = GraphManifestLoader(),
         cache: GraphLoaderCaching = GraphLoaderCache(),
         fileHandler: FileHandling = FileHandler(),
         circularDetector: GraphCircularDetecting = GraphCircularDetector(),
         shell: Shelling = Shell()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.fileHandler = fileHandler
        self.circularDetector = circularDetector
        self.shell = shell
    }
}
