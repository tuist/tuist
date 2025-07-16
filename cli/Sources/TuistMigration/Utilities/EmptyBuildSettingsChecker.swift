import FileSystem
import Foundation
import Path
import PathKit
import TuistSupport
import XcodeProj

/// An interface to check whether a project or a target has empty build settings.
public protocol EmptyBuildSettingsChecking {
    /// Checks whether a project or a target has empty build settings. If it does not, the command fails with an error.
    /// - Parameters:
    ///   - xcodeprojPath: Path to the Xcode project.
    ///   - targetName: Name of the target. When nil, the build settings of the project are checked instead.
    func check(xcodeprojPath: AbsolutePath, targetName: String?) async throws
}

enum EmptyBuildSettingsCheckerError: FatalError, Equatable {
    case missingXcodeProj(AbsolutePath)
    case missingProject
    case targetNotFound(String)
    case nonEmptyBuildSettings([String])

    var description: String {
        switch self {
        case let .missingXcodeProj(path): return "Couldn't find Xcode project at path \(path.pathString)."
        case .missingProject: return "The project's pbxproj file contains no projects."
        case let .targetNotFound(name): return "Couldn't find target with name '\(name)' in the project."
        case let .nonEmptyBuildSettings(configurations): return "The following configurations have non-empty build settings: \(configurations.joined(separator: ", "))"
        }
    }

    var type: ErrorType {
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
    private let fileSystem: FileSysteming

    // MARK: - Init

    public init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    // MARK: - EmptyBuildSettingsChecking

    public func check(xcodeprojPath: AbsolutePath, targetName: String?) async throws {
        guard try await fileSystem.exists(xcodeprojPath)
        else { throw EmptyBuildSettingsCheckerError.missingXcodeProj(xcodeprojPath) }
        let project = try XcodeProj(path: Path(xcodeprojPath.pathString))
        let pbxproj = project.pbxproj
        let buildConfigurations = try buildConfigurations(pbxproj: pbxproj, targetName: targetName)
        let nonEmptyBuildSettings = buildConfigurations.compactMap { config -> String? in
            if config.buildSettings.isEmpty { return nil }
            for (key, _) in config.buildSettings {
                Logger.current
                    .notice("The build setting '\(key)' of build configuration '\(config.name)' is not empty.")
            }
            return config.name
        }
        if !nonEmptyBuildSettings.isEmpty {
            throw EmptyBuildSettingsCheckerError.nonEmptyBuildSettings(nonEmptyBuildSettings)
        }
    }

    // MARK: - Private

    private func buildConfigurations(pbxproj: PBXProj, targetName: String?) throws -> [XCBuildConfiguration] {
        if let targetName {
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

#if DEBUG
    public class MockEmptyBuildSettingsChecker: EmptyBuildSettingsChecking {
        public init() {}

        public var invokedCheck = false
        public var invokedCheckCount = 0
        public var invokedCheckParameters: (xcodeprojPath: AbsolutePath, targetName: String?)?
        public var invokedCheckParametersList = [(xcodeprojPath: AbsolutePath, targetName: String?)]()
        public var stubbedCheckError: Error?

        public func check(xcodeprojPath: AbsolutePath, targetName: String?) throws {
            invokedCheck = true
            invokedCheckCount += 1
            invokedCheckParameters = (xcodeprojPath, targetName)
            invokedCheckParametersList.append((xcodeprojPath, targetName))
            if let error = stubbedCheckError {
                throw error
            }
        }
    }
#endif
