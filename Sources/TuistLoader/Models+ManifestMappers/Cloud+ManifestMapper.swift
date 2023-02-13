import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

enum CloudManifestMapperError: FatalError {
    /// Thrown when the cloud URL is invalid.
    case invalidCloudURL(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidCloudURL: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .invalidCloudURL(url):
            return "The cloud URL '\(url)' is not a valid URL"
        }
    }
}

extension TuistGraph.Cloud {
    static func from(manifest: ProjectDescription.Cloud) throws -> TuistGraph.Cloud {
        var cloudURL: URL!
        if let manifestCloudURL = URL(string: manifest.url) {
            cloudURL = manifestCloudURL
        } else {
            throw CloudManifestMapperError.invalidCloudURL(manifest.url)
        }
        let options = manifest.options.compactMap(TuistGraph.Cloud.Option.from)
        return TuistGraph.Cloud(url: cloudURL, projectId: manifest.projectId, options: options)
    }
}

extension TuistGraph.Cloud.Option {
    static func from(manifest: ProjectDescription.Cloud.Option) -> TuistGraph.Cloud.Option? {
        switch manifest {
        case .analytics:
            return nil
        case .disableAnalytics:
            return .disableAnalytics
        case .optional:
            return .optional
        }
    }
}
