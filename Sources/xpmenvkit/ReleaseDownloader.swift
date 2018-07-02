import Foundation

protocol ReleaseDownloading: AnyObject {
    func download(release: Release) throws
}

class ReleaseDownloader: ReleaseDownloading {
    /// URL session.
    let session: URLSession

    /// Local environment controller.
    let localEnvironmentController: LocalEnvironmentController

    init(localEnvironmentController: LocalEnvironmentController,
         session: URLSession = .shared) {
        self.localEnvironmentController = localEnvironmentController
        self.session = session
    }

    func download(release _: Release) throws {
        // TODO:
    }
}
