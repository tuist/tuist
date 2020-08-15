import PathKit
import TSCBasic
import TuistSupport
import XcodeProj

/// Defines the interface to extract the build settings from a project or a target into an .xcconfig file.
public protocol SettingsToXCConfigExtracting {
    /// Extracts the build settings from the given Xcode project or any of the targets in it.
    /// - Parameters:
    ///   - xcodeprojPath: Path to the .xcodeproj file.
    ///   - targetName: Name of the target. When nil, it extracts the settings of the project.
    ///   - xcconfigPath: Path to the .xcconfig where the build settings will be extracted.
    func extract(xcodeprojPath: AbsolutePath, targetName: String?, xcconfigPath: AbsolutePath) throws
}

public enum SettingsToXCConfigExtractorError: FatalError, Equatable {
    case missingXcodeProj(AbsolutePath)
    case missingProject
    case targetNotFound(String)

    public var description: String {
        switch self {
        case let .missingXcodeProj(path): return "Couldn't find Xcode project at path \(path.pathString)."
        case .missingProject: return "The project's pbxproj file contains no projects."
        case let .targetNotFound(name): return "Couldn't find target with name '\(name)' in the project."
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
        }
    }
}

public class SettingsToXCConfigExtractor: SettingsToXCConfigExtracting {
    public init() {}

    public func extract(xcodeprojPath: AbsolutePath, targetName: String?, xcconfigPath _: AbsolutePath) throws {
        guard FileHandler.shared.exists(xcodeprojPath) else { throw SettingsToXCConfigExtractorError.missingXcodeProj(xcodeprojPath) }
        let project = try XcodeProj(path: Path(xcodeprojPath.pathString))
        let pbxproj = project.pbxproj
        let buildConfigurations = try self.buildConfigurations(pbxproj: pbxproj, targetName: targetName)
    }

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
