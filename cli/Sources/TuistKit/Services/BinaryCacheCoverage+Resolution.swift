import TuistAlert
import TuistCache
import TuistConfig
import TuistEnvironment
import TuistServer

extension BinaryCacheCoverage {
    static let enabledVariable = "TUIST_COVERAGE_ENABLED"
    static let prefixMappingVariable = "TUIST_COVERAGE_PREFIX_MAPPING"

    /// `Tuist.swift`'s `coverage.prefixMapping`, unless `TUIST_COVERAGE_PREFIX_MAPPING` is set.
    static func resolvedPrefixMapping(config: Tuist) -> Bool {
        if Environment.current.variables[prefixMappingVariable] != nil {
            return Environment.current.isVariableTruthy(prefixMappingVariable)
        }
        return config.project.generatedProject?.generationOptions.coverage.prefixMapping == true
    }

    /// The variant a command reads and warms: `--coverage` / `--no-coverage`, then `TUIST_COVERAGE_ENABLED`,
    /// then `Tuist.swift`'s `coverage.enabled`, off otherwise. Coverage is in early access behind the
    /// `COVERAGE` client feature flag, so without it every command stays on the plain variant.
    public static func resolved(flag: Bool?, config: Tuist) -> BinaryCacheCoverage {
        guard ClientFeatureFlags.contains("COVERAGE") else {
            if flag == true {
                AlertController.current.warning(.alert(
                    "\(.command("--coverage")) is ignored: coverage is in early access.",
                    takeaway: "Set \(.command("TUIST_FEATURE_FLAG_COVERAGE=1")) to read and warm the instrumented binaries."
                ))
            }
            return .off
        }
        if let flag { return flag ? .on : .off }
        if Environment.current.variables[enabledVariable] != nil {
            return Environment.current.isVariableTruthy(enabledVariable) ? .on : .off
        }
        return BinaryCacheCoverage(config: config)
    }

    /// The variant the config carries: `Tuist.swift`'s option, or the one a generator factory resolved
    /// (`Tuist.resolvingCoverage`).
    init(config: Tuist) {
        self = config.project.generatedProject?.generationOptions.coverage.enabled == true ? .on : .off
    }
}

extension Tuist {
    /// The configuration the generators read: `coverage.enabled` holds the variant the command resolved, so the
    /// mappers that write the linker setting and turn on coverage in schemes follow the same value as the
    /// binary-cache keys, and `coverage.prefixMapping` holds `TUIST_COVERAGE_PREFIX_MAPPING` when it's set.
    func resolvingCoverage(_ coverage: BinaryCacheCoverage) -> Tuist {
        guard case var .generated(options) = project else { return self }
        options.generationOptions.coverage.enabled = coverage == .on
        options.generationOptions.coverage.prefixMapping = BinaryCacheCoverage.resolvedPrefixMapping(config: self)
        var config = self
        config.project = .generated(options)
        return config
    }
}
