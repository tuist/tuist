import Foundation
import Logging
import TuistCore
import XcodeGraph

/// Links the profile runtime into the repository's Debug builds when `Tuist.swift`'s `coverage.enabled` is on.
///
/// With coverage on, the repository's own targets come from the binary cache with coverage counters, and an
/// instrumented static binary references the profile runtime (`___llvm_profile_runtime`). A build that doesn't
/// collect coverage links no runtime, so the reference only resolves today because Tuist's `DEAD_CODE_STRIPPING`
/// default drops it; with dead stripping off, linking fails. `CLANG_COVERAGE_MAPPING_LINKER_ARGS` adds the runtime
/// at link time (`-fprofile-instr-generate`) and instruments nothing. It's written in every configuration Xcode
/// treats as Debug, the ones the instrumented variant is read for, and only for projects without an
/// `externalHash`, the rule the binary-cache keys follow. A value the project already sets is kept.
public struct CoverageLinkerSettingsProjectMapper: ProjectMapping {
    static let setting = "CLANG_COVERAGE_MAPPING_LINKER_ARGS"

    private let enabled: Bool

    public init(enabled: Bool) {
        self.enabled = enabled
    }

    public func map(project: Project) async throws -> (Project, [SideEffectDescriptor]) {
        guard enabled, project.externalHash == nil else { return (project, []) }
        Logger.current.debug("Transforming project \(project.name): Linking the profile runtime in Debug configurations")

        let configurations = Dictionary(uniqueKeysWithValues: project.settings.configurations
            .map { buildConfiguration, configuration in
                guard buildConfiguration.variant == .debug else { return (buildConfiguration, configuration) }
                var configuration = configuration ?? Configuration()
                if configuration.settings[Self.setting] == nil {
                    configuration.settings[Self.setting] = "YES"
                }
                return (buildConfiguration, configuration)
            })
        var project = project
        project.settings = Settings(
            base: project.settings.base,
            baseDebug: project.settings.baseDebug,
            configurations: configurations,
            defaultSettings: project.settings.defaultSettings,
            defaultConfiguration: project.settings.defaultConfiguration
        )
        return (project, [])
    }
}
