import Foundation
import PathKit
import TSCBasic
import TuistSupport
import XcodeProj

public enum TargetsExtractorError: FatalError, Equatable {
    case missingXcodeProj(AbsolutePath)
    case noTargets
    case failedToExtractTargets(String)
    case failedToEncode

    public var description: String {
        switch self {
        case let .missingXcodeProj(path): return "Couldn't find Xcode project at path \(path.pathString)."
        case .noTargets: return "The project doesn't have any targets."
        case .failedToEncode: return "Failed to encode targets into JSON schema"
        case let .failedToExtractTargets(reason): return "Failed to extract targets for reason: \(reason)."
        }
    }

    public var type: ErrorType {
        switch self {
        case .missingXcodeProj:
            return .abort
        case .noTargets:
            return .abort
        case .failedToExtractTargets:
            return .bug
        case .failedToEncode:
            return .bug
        }
    }
}

/// An interface to extract all targets from an xcode project, sorted by number of dependencies
public protocol TargetsExtracting {
    /// - Parameters:
    ///   - xcodeprojPath: Path to the Xcode project.
    func targetsSortedByDependencies(xcodeprojPath: AbsolutePath) throws -> [TargetDependencyCount]
}

public struct TargetDependencyCount: Encodable {
    public let targetName: String
    public let targetDependenciesNames: [String]
    public let linkedFrameworksCount: Int
}

public final class TargetsExtractor: TargetsExtracting {
    // MARK: - Init

    public init() {}

    // MARK: - EmptyBuildSettingsChecking

    public func targetsSortedByDependencies(xcodeprojPath: AbsolutePath) throws -> [TargetDependencyCount] {
        guard FileHandler.shared.exists(xcodeprojPath) else { throw TargetsExtractorError.missingXcodeProj(xcodeprojPath) }
        let pbxproj = try XcodeProj(path: Path(xcodeprojPath.pathString)).pbxproj
        let targets = pbxproj.nativeTargets + pbxproj.aggregateTargets + pbxproj.legacyTargets
        if targets.isEmpty {
            throw TargetsExtractorError.noTargets
        }
        return try sortTargetsByDependenciesCount(targets)
    }

    private func sortTargetsByDependenciesCount(_ targets: [PBXTarget]) throws -> [TargetDependencyCount] {
        try topologicalSort(targets, successors: { $0.dependencies.compactMap(\.target) })
            .reversed()
            .map { TargetDependencyCount(
                targetName: $0.name,
                targetDependenciesNames: $0.dependencies.compactMap { $0.target?.name },
                linkedFrameworksCount: try $0.frameworksBuildPhase()?.files?.count ?? 0
            ) }
    }
}
