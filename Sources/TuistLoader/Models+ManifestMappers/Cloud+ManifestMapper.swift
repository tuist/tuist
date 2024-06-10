import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

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

extension XcodeGraph.Cloud {
    static func from(manifest: ProjectDescription.Cloud) throws -> XcodeGraph.Cloud {
        var cloudURL: URL!
        if let manifestCloudURL = URL(string: manifest.url.dropSuffix("/")) {
            cloudURL = manifestCloudURL
        } else {
            throw CloudManifestMapperError.invalidCloudURL(manifest.url)
        }
        let options = manifest.options.compactMap(XcodeGraph.Cloud.Option.from)
        return XcodeGraph.Cloud(url: cloudURL, projectId: manifest.projectId, options: options)
    }
}

extension XcodeGraph.Cloud.Option {
    static func from(manifest: ProjectDescription.Cloud.Option) -> XcodeGraph.Cloud.Option? {
        switch manifest {
        case .optional:
            return .optional
        }
    }
}
