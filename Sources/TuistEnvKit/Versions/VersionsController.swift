import Basic
import Foundation
import SPMUtility
import TuistSupport

protocol VersionsControlling: AnyObject {
    typealias Installation = (AbsolutePath) throws -> Void

    func install(version: String, installation: Installation) throws
    func uninstall(version: String) throws
    func path(version: String) -> AbsolutePath
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

    static func == (lhs: InstalledVersion, rhs: InstalledVersion) -> Bool {
        switch (lhs, rhs) {
        case let (.semver(lhsVersion), .semver(rhsVersion)):
            return lhsVersion == rhsVersion
        case let (.reference(lhsRef), .reference(rhsRef)):
            return lhsRef == rhsRef
        default:
            return false
        }
    }
}

class VersionsController: VersionsControlling {
    // MARK: - VersionsControlling

    func install(version: String, installation: Installation) throws {
        let tmpDir = try TemporaryDirectory(removeTreeOnDeinit: true)

        try installation(tmpDir.path)

        // Copy only if there's file in the folder
        if !tmpDir.path.glob("*").isEmpty {
            let dstPath = path(version: version)
            if FileHandler.shared.exists(dstPath) {
                try FileHandler.shared.delete(dstPath)
            }
            try FileHandler.shared.copy(from: tmpDir.path, to: dstPath)
        }
    }

    func uninstall(version: String) throws {
        let path = self.path(version: version)
        if FileHandler.shared.exists(path) {
            try FileHandler.shared.delete(path)
        }
    }

    func path(version: String) -> AbsolutePath {
        return Environment.shared.versionsDirectory.appending(component: version)
    }

    func versions() -> [InstalledVersion] {
        return Environment.shared.versionsDirectory.glob("*").map { path in
            let versionStringValue = path.components.last!
            if let version = Version(string: versionStringValue) {
                return InstalledVersion.semver(version)
            } else {
                return InstalledVersion.reference(versionStringValue)
            }
        }
    }

    func semverVersions() -> [Version] {
        return versions().compactMap { version in
            if case let InstalledVersion.semver(semver) = version {
                return semver
            }
            return nil
        }
    }
}
