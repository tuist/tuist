import Foundation
import ProjectDescription
import TSCBasic
import struct TSCUtility.Version
import TuistGraph
import TuistSupport

enum CacheProfileError: FatalError, Equatable {
    case invalidVersion(string: String)

    var description: String {
        switch self {
        case let .invalidVersion(string):
            return "Invalid version string \(string)"
        }
    }

    var type: ErrorType {
        switch self {
        case .invalidVersion:
            return .abort
        }
    }
}

extension TuistGraph.Cache {
    static func from(
        manifest: ProjectDescription.Cache,
        generatorPaths: GeneratorPaths
    ) throws -> TuistGraph.Cache {
        let path = try manifest.path.map { try generatorPaths.resolve(path: $0) }
        let profiles = try manifest.profiles.map(TuistGraph.Cache.Profile.from(manifest:))
        return TuistGraph.Cache(profiles: profiles, path: path)
    }
}

extension TuistGraph.Cache.Profile {
    static func from(manifest: ProjectDescription.Cache.Profile) throws -> TuistGraph.Cache.Profile {
        var resolvedVersion: TSCUtility.Version?

        if let versionString = manifest.os {
            guard let version = versionString.version() else {
                throw CacheProfileError.invalidVersion(string: versionString)
            }
            resolvedVersion = version
        }

        return TuistGraph.Cache.Profile(
            name: manifest.name,
            configuration: manifest.configuration,
            device: manifest.device,
            os: resolvedVersion
        )
    }
}
