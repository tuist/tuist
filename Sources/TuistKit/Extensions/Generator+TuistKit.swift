import Foundation
import TuistGenerator
import TuistLoader

extension Generator {
    /// Initializes a generator instance with all the dependencies that are specific to Tuist.
    convenience init() {
        let manifestLoader = ManifestLoader()
        let manifestLinter = ManifestLinter()
        let modelLoader = GeneratorModelLoader(manifestLoader: manifestLoader, manifestLinter: manifestLinter)
        self.init(modelLoader: modelLoader)
    }
}
