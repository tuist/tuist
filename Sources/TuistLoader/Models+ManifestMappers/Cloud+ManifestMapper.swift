import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import XcodeProjectGenerator
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

extension XcodeProjectGenerator.Cloud {
    static func from(manifest: ProjectDescription.Cloud) throws -> XcodeProjectGenerator.Cloud {
        var cloudURL: URL!
        if let manifestCloudURL = URL(string: manifest.url.dropSuffix("/")) {
            cloudURL = manifestCloudURL
        } else {
            throw CloudManifestMapperError.invalidCloudURL(manifest.url)
        }
        let options = manifest.options.compactMap(XcodeProjectGenerator.Cloud.Option.from)
        return XcodeProjectGenerator.Cloud(url: cloudURL, projectId: manifest.projectId, options: options)
    }
}

extension XcodeProjectGenerator.Cloud.Option {
    static func from(manifest: ProjectDescription.Cloud.Option) -> XcodeProjectGenerator.Cloud.Option? {
        switch manifest {
        case .optional:
            return .optional
        }
    }
}
