import Foundation
import TSCBasic
import struct TSCUtility.Version
import TuistSupport

protocol VersionsControlling: AnyObject {
    typealias Installation = (AbsolutePath) throws -> Void

    func install(version: String, installation: Installation) throws
    func uninstall(version: String) throws
    func path(version: String) throws -> AbsolutePath
    func versions() -> [InstalledVersion]
    func semverVersions() -> [Version]
}

enum InstalledVersion: CustomStringConvertible, Equatable {
    case semver(Version)
    case reference(String)

    var description: String {
        switch self {
        case let .reference(value): return value
        case let .semver(value): return value.description
        }
    }
}

class VersionsController: VersionsControlling {
    // MARK: - VersionsControlling

    func install(version: String, installation: Installation) throws {
        try withTemporaryDirectory { tmpDir in
            try installation(tmpDir)

            // Copy only if there's file in the folder
            if !tmpDir.glob("*").isEmpty {
                let dstPath = path(version: version)
                if FileHandler.shared.exists(dstPath) {
                    try FileHandler.shared.delete(dstPath)
                }
                try FileHandler.shared.copy(from: tmpDir, to: dstPath)
            }
        }
    }

    func uninstall(version: String) throws {
        let path = self.path(version: version)
        if FileHandler.shared.exists(path) {
            try FileHandler.shared.delete(path)
        }
    }

    func path(version: String) -> AbsolutePath {
        Environment.shared.versionsDirectory.appending(component: version)
    }

    func versions() -> [InstalledVersion] {
        Environment.shared.versionsDirectory.glob("*").map { path in
            let versionStringValue = path.components.last!
            if let version = Version(versionStringValue) {
                return InstalledVersion.semver(version)
            } else {
                return InstalledVersion.reference(versionStringValue)
            }
        }
    }

    func semverVersions() -> [Version] {
        versions().compactMap { version in
            if case let InstalledVersion.semver(semver) = version {
                return semver
            }
            return nil
        }.sorted()
    }
}
