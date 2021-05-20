import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

enum LabManifestMapperError: FatalError {
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

extension TuistGraph.Lab {
    static func from(manifest: ProjectDescription.Lab) throws -> TuistGraph.Lab {
        var cloudURL: URL!
        if let manifestCloudURL = URL(string: manifest.url) {
            cloudURL = manifestCloudURL
        } else {
            throw LabManifestMapperError.invalidCloudURL(manifest.url)
        }
        let options = manifest.options.map(TuistGraph.Lab.Option.from)
        return TuistGraph.Lab(url: cloudURL, projectId: manifest.projectId, options: options)
    }
}

extension TuistGraph.Lab.Option {
    static func from(manifest: ProjectDescription.Lab.Option) -> TuistGraph.Lab.Option {
        switch manifest {
        case .insights:
            return .insights
        }
    }
}
