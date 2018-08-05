import Basic
import Foundation
import TuistCore

/// Protocol that defines the interface of the context that is used during the graph loading.
@available(*, deprecated, message: "The context approach for injecting dependencies is deprecated. Inject dependencies through the constructor instead.")
protocol GraphLoaderContexting: Contexting {
    /// Manifest loader that is used to get a JSON representation of the manifests.
    var manifestLoader: GraphManifestLoading { get }

    /// Contains a reference to the manifests that are parsed during the graph loading.
    var cache: GraphLoaderCaching { get }

    /// Circular dependency detector.
    var circularDetector: GraphCircularDetecting { get }
}

/// Object passed during the graph loading that contains utils to be used.
class GraphLoaderContext: Context, GraphLoaderContexting {
    /// Manifest loader. It's used to get a JSON representation of the manifests.
    let manifestLoader: GraphManifestLoading

    /// Contains a reference to the manifests that are parsed during the graph loading.
    let cache: GraphLoaderCaching

    /// Circular dependency detector.
    let circularDetector: GraphCircularDetecting

    init(manifestLoader: GraphManifestLoading = GraphManifestLoader(),
         cache: GraphLoaderCaching = GraphLoaderCache(),
         fileHandler: FileHandling = FileHandler(),
         circularDetector: GraphCircularDetecting = GraphCircularDetector(),
         printer: Printing = Printer()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.circularDetector = circularDetector
        super.init(fileHandler: fileHandler, printer: printer)
    }

    init(context: Context,
         manifestLoader: GraphManifestLoading = GraphManifestLoader(),
         cache: GraphLoaderCaching = GraphLoaderCache(),
         circularDetector: GraphCircularDetecting = GraphCircularDetector()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.circularDetector = circularDetector
        super.init(fileHandler: context.fileHandler, printer: context.printer)
    }
}
