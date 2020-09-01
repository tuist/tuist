import Foundation
import PathKit
import TSCBasic
import TuistSupport
import XcodeProj

/// An interface to extract all targets from an xcode project, sorted by number of dependencies
public protocol TargetsExtracting {
    /// - Parameters:
    ///   - xcodeprojPath: Path to the Xcode project.
    func targetsSortedByDependencies(xcodeprojPath: AbsolutePath) throws -> [(targetName: String, dependenciesCount: Int)]
}

public final class TargetsExtractor: TargetsExtracting {
    // MARK: - Init

    public init() {}

    // MARK: - EmptyBuildSettingsChecking

    public func targetsSortedByDependencies(xcodeprojPath: AbsolutePath) throws -> [(targetName: String, dependenciesCount: Int)] {
        guard FileHandler.shared.exists(xcodeprojPath) else { throw TargetsExtractorError.missingXcodeProj(xcodeprojPath) }
        let pbxproj = try XcodeProj(path: Path(xcodeprojPath.pathString)).pbxproj
        let targets = pbxproj.nativeTargets + pbxproj.aggregateTargets + pbxproj.legacyTargets
        if targets.isEmpty {
            throw TargetsExtractorError.noTargets
        }
        do {
            return try sortTargetsByDependenciesCount(targets)
        } catch {
            throw TargetsExtractorError.failedToExtractTargets(error.localizedDescription)
        }
    }

    private func sortTargetsByDependenciesCount(_ targets: [PBXTarget]) throws -> [(targetName: String, dependenciesCount: Int)] {
        let sortedTargets = try targets.sorted { lTarget, rTarget -> Bool in
            let lCount = try countDependencies(of: lTarget)
            let rCount = try countDependencies(of: rTarget)
            if lCount == rCount {
                return lTarget.name < rTarget.name
            }
            return lCount < rCount
        }
        return try sortedTargets.map { (targetName: $0.name, dependenciesCount: try countDependencies(of: $0)) }
    }

    private func countDependencies(of target: PBXTarget) throws -> Int {
        var count = target.dependencies.count
        if let frameworkFiles = try target.frameworksBuildPhase()?.files {
            count += frameworkFiles.count
        }
        return count
    }
}

enum TargetsExtractorError: FatalError, Equatable {
    case missingXcodeProj(AbsolutePath)
    case missingProject
    case noTargets
    case failedToExtractTargets(String)

    public var description: String {
        switch self {
        case let .missingXcodeProj(path): return "Couldn't find Xcode project at path \(path.pathString)."
        case .missingProject: return "The project's pbxproj file contains no projects."
        case .noTargets: return "The project doesn't have any targets"
        case let .failedToExtractTargets(reason): return "Failed to extract targets for reason: \(reason)"
        }
    }

    public var type: ErrorType {
        switch self {
        case .missingXcodeProj:
            return .abort
        case .missingProject:
            return .abort
        case .noTargets:
            return .abort
        case .failedToExtractTargets:
            return .bug
        }
    }
}
