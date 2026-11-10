import Testing
import XcodeGraph

@testable import TuistGenerator
@testable import TuistTesting

struct TargetAppendingListSettingsTests {
    private let key = "EXCLUDED_SOURCE_FILE_NAMES"

    @Test func appendingListSettings_whenSettingsAreNil_inheritsAndAppends() {
        let target = Target.test(settings: nil)

        let got = target.appendingListSettings([key: ["A"]])

        #expect(got.settings?.base[key] == .array(["$(inherited)", "A"]))
    }

    @Test func appendingListSettings_keepsExistingArrayAndSkipsDuplicates() {
        let target = Target.test(settings: Settings.test(base: [key: .array(["Mock*.swift", "A"])]))

        let got = target.appendingListSettings([key: ["A", "B"]])

        #expect(got.settings?.base[key] == .array(["Mock*.swift", "A", "B"]))
    }

    @Test func appendingListSettings_convertsExistingString() {
        let target = Target.test(settings: Settings.test(base: [key: .string("Mock*.swift")]))

        let got = target.appendingListSettings([key: ["A"]])

        #expect(got.settings?.base[key] == .array(["Mock*.swift", "A"]))
    }

    @Test func appendingListSettings_appendsToConfigurationsAndBaseDebugThatOverrideTheKey() {
        let target = Target.test(settings: Settings(
            base: [:],
            baseDebug: [key: .array(["Debug*.swift"])],
            configurations: [
                .release("Release"): Configuration(settings: [key: .array(["Release*.swift"])]),
                .debug("Debug"): Configuration(settings: ["OTHER": .string("value")]),
            ]
        ))

        let got = target.appendingListSettings([key: ["A"]])

        #expect(got.settings?.baseDebug[key] == .array(["Debug*.swift", "A"]))
        #expect(got.settings?.configurations[.release("Release")]??.settings[key] == .array(["Release*.swift", "A"]))
        #expect(got.settings?.configurations[.debug("Debug")]??.settings[key] == nil)
    }
}
