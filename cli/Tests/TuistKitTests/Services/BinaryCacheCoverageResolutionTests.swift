import Testing
import TuistCache
import TuistConfig
import TuistEnvironment
import TuistTesting
@testable import TuistKit

struct BinaryCacheCoverageResolutionTests {
    private func config(coverage: Bool) -> Tuist {
        .test(project: .generated(.test(generationOptions: .test(coverage: .init(enabled: coverage)))))
    }

    @Test(.withMockedEnvironment(), arguments: [
        // flag, TUIST_COVERAGE_ENABLED, Tuist.swift, expected
        (Bool?.none, String?.none, false, BinaryCacheCoverage.off),
        (nil, nil, true, .on),
        (nil, "1", false, .on),
        (nil, "true", false, .on),
        (nil, "0", true, .off),
        (nil, "NO", true, .off),
        (true, nil, false, .on),
        (true, "0", false, .on),
        (false, nil, true, .off),
        (false, "1", true, .off),
    ])
    func resolvesFlagThenEnvironmentThenConfig(
        flag: Bool?,
        variable: String?,
        option: Bool,
        expected: BinaryCacheCoverage
    ) throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"
        environment.variables["TUIST_COVERAGE_ENABLED"] = variable

        #expect(BinaryCacheCoverage.resolved(flag: flag, config: config(coverage: option)) == expected)
    }

    @Test(.withMockedEnvironment(), arguments: [Bool?.none, true])
    func staysOff_withoutTheFeatureFlag(flag: Bool?) throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_COVERAGE_ENABLED"] = "1"

        #expect(BinaryCacheCoverage.resolved(flag: flag, config: config(coverage: true)) == .off)
    }

    @Test(.withMockedEnvironment())
    func staysOff_forProjectsThatAreNotGenerated() throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_FEATURE_FLAG_COVERAGE"] = "1"

        #expect(BinaryCacheCoverage.resolved(flag: nil, config: .test(project: .testXcodeProject())) == .off)
    }

    @Test(arguments: [BinaryCacheCoverage.on, .off], [false, true])
    func resolvingCoverage_setsWhatTheGeneratorsRead(coverage: BinaryCacheCoverage, option: Bool) {
        let got = config(coverage: option).resolvingCoverage(coverage)

        #expect(got.project.generatedProject?.generationOptions.coverage.enabled == (coverage == .on))
        #expect(BinaryCacheCoverage(config: got) == coverage)
    }

    @Test(.withMockedEnvironment(), arguments: [
        // TUIST_COVERAGE_PREFIX_MAPPING, Tuist.swift, expected
        (String?.none, false, false),
        (nil, true, true),
        ("1", false, true),
        ("0", true, false),
    ])
    func resolvingCoverage_appliesThePrefixMappingVariable(variable: String?, option: Bool, expected: Bool) throws {
        let environment = try #require(Environment.mocked)
        environment.variables["TUIST_COVERAGE_PREFIX_MAPPING"] = variable
        let config = Tuist.test(project: .generated(.test(generationOptions: .test(coverage: .init(prefixMapping: option)))))

        let got = config.resolvingCoverage(.off)

        #expect(got.project.generatedProject?.generationOptions.coverage.prefixMapping == expected)
    }
}
