import Basic
import Foundation
import TuistCore
import Utility

enum ResolvedVersion: Equatable {
    case bin(AbsolutePath)
    case versionFile(AbsolutePath, String)
    case undefined

    static func == (lhs: ResolvedVersion, rhs: ResolvedVersion) -> Bool {
        switch (lhs, rhs) {
        case let (.bin(lhsPath), .bin(rhsPath)):
            return lhsPath == rhsPath
        case let (.versionFile(lhsPath, lhsValue), .versionFile(rhsPath, rhsValue)):
            return lhsValue == rhsValue && lhsPath == rhsPath
        case (.undefined, .undefined):
            return true
        default:
            return false
        }
    }
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
            return "Cannot read the version file at path \(path.asString)."
        }
    }

    static func == (lhs: VersionResolverError, rhs: VersionResolverError) -> Bool {
        switch (lhs, rhs) {
        case let (.readError(lhsPath), .readError(rhsPath)):
            return lhsPath == rhsPath
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
        return try resolveTraversing(from: path)
    }

    // MARK: - Fileprivate

    fileprivate func resolveTraversing(from path: AbsolutePath) throws -> ResolvedVersion {
        let versionPath = path.appending(component: Constants.versionFileName)
        let binPath = path.appending(component: Constants.binFolderName)
        if fileManager.fileExists(atPath: binPath.asString) {
            return .bin(binPath)
        } else if fileManager.fileExists(atPath: versionPath.asString) {
            return try resolveVersionFile(path: versionPath)
        }
        if path.components.count > 1 {
            return try resolveTraversing(from: path.parentDirectory)
        }
        return .undefined
    }

    fileprivate func resolveVersionFile(path: AbsolutePath) throws -> ResolvedVersion {
        var value: String!
        do {
            value = try String(contentsOf: URL(fileURLWithPath: path.asString))
        } catch {
            throw VersionResolverError.readError(path: path)
        }
        return ResolvedVersion.versionFile(path, value)
    }
}
