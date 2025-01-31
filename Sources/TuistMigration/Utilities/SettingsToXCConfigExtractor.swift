import FileSystem
import Foundation
import Path
import PathKit
import ServiceContextModule
import TuistSupport
import XcodeProj

/// Defines the interface to extract the build settings from a project or a target into an .xcconfig file.
public protocol SettingsToXCConfigExtracting {
    /// Extracts the build settings from the given Xcode project or any of the targets in it.
    /// - Parameters:
    ///   - xcodeprojPath: Path to the .xcodeproj file.
    ///   - targetName: Name of the target. When nil, it extracts the settings of the project.
    ///   - xcconfigPath: Path to the .xcconfig where the build settings will be extracted.
    func extract(xcodeprojPath: AbsolutePath, targetName: String?, xcconfigPath: AbsolutePath) async throws
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

public final class SettingsToXCConfigExtractor: SettingsToXCConfigExtracting {
    private let fileSystem: FileSysteming

    public init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    public func extract(xcodeprojPath: AbsolutePath, targetName: String?, xcconfigPath: AbsolutePath) async throws {
        guard try await fileSystem.exists(xcodeprojPath)
        else { throw SettingsToXCConfigExtractorError.missingXcodeProj(xcodeprojPath) }
        let project = try XcodeProj(path: Path(xcodeprojPath.pathString))
        let pbxproj = project.pbxproj
        let buildConfigurations = try buildConfigurations(pbxproj: pbxproj, targetName: targetName)

        if buildConfigurations.isEmpty {
            ServiceContext.current?.logger?.notice("The list of configurations is empty. Exiting...")
            return
        }

        let repeatedBuildSettingsKeys = buildConfigurations.reduce(into: Set<String>()) { acc, next in
            if acc.isEmpty { acc.formUnion(next.buildSettings.keys) } else { acc.formIntersection(next.buildSettings.keys) }
        }

        /// We get the build settings that are in common to define them as SETTING_KEY=SETTING_VALUE
        /// Otherwise, we have to define them as SETTING_KEY[config=Config]=SETTING_VALUE
        let commonBuildSettings = repeatedBuildSettingsKeys.filter { buildSetting -> Bool in
            let values = buildConfigurations.map { $0.buildSettings[buildSetting]! }
            let stringValues = values.compactMap { $0 as? String }
            if values.count != stringValues.count { return false }
            return Set(stringValues).count == 1
        }

        var commonBuildSettingsLines: [String] = []
        var buildSettingsLines: [String] = []

        // Common build settings
        for setting in commonBuildSettings {
            let value = buildConfigurations.first!.buildSettings[setting]!
            commonBuildSettingsLines.append("\(setting)=\(flattenedValue(from: value))")
        }

        // Per-configuration build settings
        for configuration in buildConfigurations {
            for (key, value) in configuration.buildSettings {
                if commonBuildSettings.contains(key) { continue }
                buildSettingsLines.append("\(key)[config=\(configuration.name)]=\(flattenedValue(from: value))")
            }
        }

        if try await !fileSystem.exists(xcconfigPath.parentDirectory) {
            try FileHandler.shared.createFolder(xcconfigPath.parentDirectory)
        }
        let buildSettingsContent = [
            commonBuildSettingsLines.sorted().joined(separator: "\n"),
            buildSettingsLines.sorted().joined(separator: "\n"),
        ].joined(separator: "\n\n")
        try FileHandler.shared.write(buildSettingsContent, path: xcconfigPath, atomically: true)

        ServiceContext.current?.alerts?
            .append(.success(.alert("Build settings successfully extracted into \(xcconfigPath.pathString)")))
    }

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

    private func flattenedValue(from value: Any) -> String {
        var flattened: String
        // We need to flatten the array into string to avoid expressions of `SETTING_KEY=["VALUE1", "VALUE2", ...]`
        // Xcode rather understands only expressions, such as `SETTING_KEY=VALUE1 VALUE2 ...`
        if let arrayValue = value as? [Any] {
            flattened = arrayValue.map { "\($0)" }.joined(separator: " ")
        } else {
            flattened = "\(value)"
        }

        return flattened
    }
}
