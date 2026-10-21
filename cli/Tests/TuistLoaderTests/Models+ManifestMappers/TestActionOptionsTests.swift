import Foundation
import ProjectDescription
import Testing

struct TestActionOptionsTests {
    @Test(arguments: [
        (Bool?.none, TestActionOptions.CoverageMode.inherit),
        (true, .enabled),
        (false, .disabled),
    ])
    func options_mapsCoverageToTheMode(coverage: Bool?, expected: TestActionOptions.CoverageMode) {
        #expect(TestActionOptions.options(coverage: coverage).codeCoverage == expected)
    }

    /// The deprecated Boolean keeps compiling for manifests that read it, and reads `false` for a scheme that
    /// inherits.
    @available(*, deprecated)
    @Test(arguments: [
        (Bool?.none, false),
        (true, true),
        (false, false),
    ])
    func coverage_readsWhetherTheSchemeTurnsCoverageOnItself(coverage: Bool?, expected: Bool) {
        var options = TestActionOptions.options(coverage: coverage)

        #expect(options.coverage == expected)

        options.coverage = !expected
        #expect(options.codeCoverage == (expected ? .disabled : .enabled))
    }

    @Test(arguments: [
        (TestActionOptions.CoverageMode.inherit, Bool?.none),
        (.enabled, true),
        (.disabled, false),
    ])
    func codable_keepsTheCoverageKey(mode: TestActionOptions.CoverageMode, encoded: Bool?) throws {
        var options = TestActionOptions.options(language: "en", codeCoverageTargets: [.target("App")])
        options.codeCoverage = mode

        let data = try JSONEncoder().encode(options)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(json["coverage"] as? Bool == encoded)
        #expect(json.keys.contains("coverage") == (encoded != nil))
        #expect(try JSONDecoder().decode(TestActionOptions.self, from: data) == options)
    }
}
