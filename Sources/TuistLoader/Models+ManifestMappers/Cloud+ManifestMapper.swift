import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

enum LabManifestMapperError: FatalError {
    /// Thrown when the lab URL is invalid.
    case invalidLabURL(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidLabURL: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .invalidLabURL(url):
            return "The lab URL '\(url)' is not a valid URL"
        }
    }
}

extension TuistGraph.Lab {
    static func from(manifest: ProjectDescription.Lab) throws -> TuistGraph.Lab {
        var labURL: URL!
        if let manifestLabURL = URL(string: manifest.url) {
            labURL = manifestLabURL
        } else {
            throw LabManifestMapperError.invalidLabURL(manifest.url)
        }
        let options = manifest.options.map(TuistGraph.Lab.Option.from)
        return TuistGraph.Lab(url: labURL, projectId: manifest.projectId, options: options)
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
