import Foundation
import TuistCore
import XcodeProj

public protocol RunpathSearchPathsLinting {
    func lint(workspace: WorkspaceDescriptor) -> [LintingIssue]
}

/// Xcode 27's dyld refuses to load binaries with more than 256 `LC_RPATH` load commands ("too many LC_RPATHs").
/// The linter only sees the `LD_RUNPATH_SEARCH_PATHS` written into the generated projects, not the ones coming from
/// xcconfig files, linker flags, or the build system itself, so it warns with some headroom below the limit.
public struct RunpathSearchPathsLinter: RunpathSearchPathsLinting {
    static let maximumRunpathSearchPaths = 256
    static let implicitRunpathSearchPathsHeadroom = 6
    private static let inheritedValues: Set<String> = ["$(inherited)", "${inherited}", "$inherited"]

    public init() {}

    public func lint(workspace: WorkspaceDescriptor) -> [LintingIssue] {
        workspace.projectDescriptors.flatMap(lint(project:))
    }

    private func lint(project: ProjectDescriptor) -> [LintingIssue] {
        guard let rootObject = project.xcodeProj.pbxproj.rootObject else { return [] }
        let warningThreshold = Self.maximumRunpathSearchPaths - Self.implicitRunpathSearchPathsHeadroom

        var projectRunpathSearchPaths: [String: [String]] = [:]
        for configuration in rootObject.buildConfigurationList?.buildConfigurations ?? [] {
            projectRunpathSearchPaths[configuration.name] = runpathSearchPaths(of: configuration)
        }

        return rootObject.targets.compactMap { target in
            let largestConfiguration = (target.buildConfigurationList?.buildConfigurations ?? [])
                .map { configuration -> (name: String, count: Int) in
                    var values = runpathSearchPaths(of: configuration)
                    if values.contains(where: Self.inheritedValues.contains) {
                        values.append(contentsOf: projectRunpathSearchPaths[configuration.name] ?? [])
                    }
                    let count = Set(values.filter { !Self.inheritedValues.contains($0) }).count
                    return (configuration.name, count)
                }
                .max { $0.count < $1.count }

            guard let largestConfiguration, largestConfiguration.count > warningThreshold else { return nil }
            let projectName = project.xcodeprojPath.basename
            let count = largestConfiguration.count
            let configurationName = largestConfiguration.name
            let limit = Self.maximumRunpathSearchPaths
            return LintingIssue(
                reason: """
                The target '\(target.name)' in '\(projectName)' has \(count) run path search paths in its \
                '\(configurationName)' configuration. Xcode 27 fails to load binaries with more than \(limit) LC_RPATH \
                entries ("too many LC_RPATHs"), and the build system can add more at link time. Reduce \
                LD_RUNPATH_SEARCH_PATHS, for example by giving unit test targets a host application.
                """,
                severity: .warning
            )
        }
    }

    private func runpathSearchPaths(of configuration: XCBuildConfiguration) -> [String] {
        switch configuration.buildSettings["LD_RUNPATH_SEARCH_PATHS"] {
        case let .array(values):
            return values.flatMap(splitSettingValue)
        case let .string(value):
            return splitSettingValue(value)
        case .none:
            return []
        }
    }

    /// Splits a build setting string the way Xcode does: on whitespace, keeping quoted values together.
    private func splitSettingValue(_ value: String) -> [String] {
        var values: [String] = []
        var current = ""
        var quote: Character?
        for character in value {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
            } else if character.isWhitespace {
                if !current.isEmpty {
                    values.append(current)
                    current = ""
                }
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty {
            values.append(current)
        }
        return values
    }
}
