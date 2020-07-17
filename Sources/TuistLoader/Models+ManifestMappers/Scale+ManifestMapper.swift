import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport

enum ScaleManifestMapperError: FatalError {
    /// Thrown when the scale URL is invalid.
    case invalidScaleURL(String)

    /// Error type.
    var type: ErrorType {
        switch self {
        case .invalidScaleURL: return .abort
        }
    }

    /// Error description.
    var description: String {
        switch self {
        case let .invalidScaleURL(url):
            return "The scale URL '\(url)' is not a valid URL"
        }
    }
}

extension TuistCore.Scale {
    static func from(manifest: ProjectDescription.Scale) throws -> TuistCore.Scale {
        var scaleURL: URL!
        if let manifestScaleURL = URL(string: manifest.url) {
            scaleURL = manifestScaleURL
        } else {
            throw ScaleManifestMapperError.invalidScaleURL(manifest.url)
        }
        let options = manifest.options.map(TuistCore.Scale.Option.from)
        return TuistCore.Scale(url: scaleURL, projectId: manifest.projectId, options: options)
    }
}

extension TuistCore.Scale.Option {
    static func from(manifest: ProjectDescription.Scale.Option) -> TuistCore.Scale.Option {
        switch manifest {
        case .insights:
            return .insights
        }
    }
}
