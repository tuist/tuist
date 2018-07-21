import Basic
import Foundation
import xpmcore

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

    /// Initializes the context with its attributes.
    ///
    /// - Parameters:
    ///   - manifestLoader: Manifest loader that is used to get a JSON representation of the manifests.
    ///   - cache: Contains a reference to the manifests that are parsed during the graph loading.
    ///   - fileHandler: Util to handle files.
    ///   - circularDetector: Circular dependency detector.
    ///   - shell: shell.
    ///   - printer: printer.
    init(manifestLoader: GraphManifestLoading = GraphManifestLoader(),
         cache: GraphLoaderCaching = GraphLoaderCache(),
         fileHandler: FileHandling = FileHandler(),
         circularDetector: GraphCircularDetecting = GraphCircularDetector(),
         shell: Shelling = Shell(),
         printer: Printing = Printer()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.circularDetector = circularDetector
        super.init(fileHandler: fileHandler, shell: shell, printer: printer)
    }

    /// Initializes the graph loader context with a context and the extra attributes that the graph loader context has.
    ///
    /// - Parameters:
    ///   - context: base context.
    ///   - manifestLoader: manifest loader.
    ///   - cache: graph loader cache.
    ///   - circularDetector: circular dependencies detector.
    init(context: Context,
         manifestLoader: GraphManifestLoading = GraphManifestLoader(),
         cache: GraphLoaderCaching = GraphLoaderCache(),
         circularDetector: GraphCircularDetecting = GraphCircularDetector()) {
        self.manifestLoader = manifestLoader
        self.cache = cache
        self.circularDetector = circularDetector
        super.init(fileHandler: context.fileHandler, shell: context.shell, printer: context.printer)
    }
}
