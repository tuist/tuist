import Foundation
import TSCBasic
import TuistSupport

enum ResolvedVersion: Equatable {
    case bin(AbsolutePath)
    case versionFile(AbsolutePath, String)
    case undefined
}

protocol VersionResolving: AnyObject {
    func resolve(path: AbsolutePath) throws -> ResolvedVersion
}

enum VersionResolverError: FatalError, Equatable {
    case readError(path: AbsolutePath)

    var type: ErrorType {
        switch self {
        case .readError: return .abort
        }
    }

    var description: String {
        switch self {
        case let .readError(path):
            return "Cannot read the version file at path \(path.pathString)."
        }
    }
}

class VersionResolver: VersionResolving {
    // MARK: - Attributes

    private let settingsController: SettingsControlling
    private let fileManager: FileManager = .default

    // MARK: - Init

    init(settingsController: SettingsControlling = SettingsController()) {
        self.settingsController = settingsController
    }

    // MARK: - VersionResolving

    func resolve(path: AbsolutePath) throws -> ResolvedVersion {
        try resolveTraversing(from: path)
    }

    // MARK: - Fileprivate

    private func resolveTraversing(from path: AbsolutePath) throws -> ResolvedVersion {
        let versionPath = path.appending(component: Constants.versionFileName)
        let binPath = path.appending(component: Constants.binFolderName)
        if fileManager.fileExists(atPath: binPath.pathString) {
            return .bin(binPath)
        } else if fileManager.fileExists(atPath: versionPath.pathString) {
            return try resolveVersionFile(path: versionPath)
        }
        if path.components.count > 1 {
            return try resolveTraversing(from: path.parentDirectory)
        }
        return .undefined
    }

    private func resolveVersionFile(path: AbsolutePath) throws -> ResolvedVersion {
        var value: String!
        do {
            value = try String(contentsOf: URL(fileURLWithPath: path.pathString)).trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            throw VersionResolverError.readError(path: path)
        }
        return ResolvedVersion.versionFile(path, value)
    }
}
