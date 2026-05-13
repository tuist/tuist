import TuistLogging

enum SwifterPMPackageInfoCacheLoaderError: FatalError {
    case failedToLoadPackageInfo(path: String, error: Error)

    var type: ErrorType {
        .bug
    }

    var description: String {
        switch self {
        case let .failedToLoadPackageInfo(path, error):
            "Failed to load SwifterPM package info at \(path): \(error.localizedDescription)"
        }
    }
}
