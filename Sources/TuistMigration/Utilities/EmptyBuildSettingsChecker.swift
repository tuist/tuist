import Foundation
import PathKit
import TSCBasic
import TuistSupport
import XcodeProj

/// An interface to check whether a project or a target has empty build settings.
public protocol EmptyBuildSettingsChecking {
    /// Checks whether a project or a target has empty build settings. If it does not, the command fails with an error.
    /// - Parameters:
    ///   - xcodeprojPath: Path to the Xcode project.
    ///   - targetName: Name of the target. When nil, the build settings of the project are checked instead.
    func check(xcodeprojPath: AbsolutePath, targetName: String?) throws
}

enum EmptyBuildSettingsCheckerError: FatalError, Equatable {
    case missingXcodeProj(AbsolutePath)
    case missingProject
    case targetNotFound(String)
    case nonEmptyBuildSettings([String])

    public var description: String {
        switch self {
        case let .missingXcodeProj(path): return "Couldn't find Xcode project at path \(path.pathString)."
        case .missingProject: return "The project's pbxproj file contains no projects."
        case let .targetNotFound(name): return "Couldn't find target with name '\(name)' in the project."
        case let .nonEmptyBuildSettings(configurations): return "The following configurations have non-empty build setttings: \(configurations.joined(separator: ", "))"
        }
    }

    public var type: ErrorType {
        switch self {
        case .missingXcodeProj:
            return .abort
        case .missingProject:
            return .abort
        case .targetNotFound:
            return .abort
        case .nonEmptyBuildSettings:
            return .abortSilent
        }
    }
}

public class EmptyBuildSettingsChecker: EmptyBuildSettingsChecking {
    // MARK: - Init

    public init() {}

    // MARK: - EmptyBuildSettingsChecking

    public func check(xcodeprojPath: AbsolutePath, targetName: String?) throws {
        guard FileHandler.shared.exists(xcodeprojPath)
        else { throw EmptyBuildSettingsCheckerError.missingXcodeProj(xcodeprojPath) }
        let project = try XcodeProj(path: Path(xcodeprojPath.pathString))
        let pbxproj = project.pbxproj
        let buildConfigurations = try buildConfigurations(pbxproj: pbxproj, targetName: targetName)
        let nonEmptyBuildSettings = buildConfigurations.compactMap { config -> String? in
            if config.buildSettings.isEmpty { return nil }
            config.buildSettings.forEach { key, _ in
                logger.info("The build setting '\(key)' of build configuration '\(config.name)' is not empty.")
            }
            return config.name
        }
        if !nonEmptyBuildSettings.isEmpty {
            throw EmptyBuildSettingsCheckerError.nonEmptyBuildSettings(nonEmptyBuildSettings)
        }
    }

    // MARK: - Private

    private func buildConfigurations(pbxproj: PBXProj, targetName: String?) throws -> [XCBuildConfiguration] {
        if let targetName = targetName {
            guard let target = pbxproj.targets(named: targetName).first else {
                throw SettingsToXCConfigExtractorError.targetNotFound(targetName)
            }
            return target.buildConfigurationList!.buildConfigurations
        } else {
            guard let project = pbxproj.projects.first else {
                throw SettingsToXCConfigExtractorError.missingProject
            }
            return project.buildConfigurationList.buildConfigurations
        }
    }
}
