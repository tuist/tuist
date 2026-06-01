import Path
import Testing
import TuistEnvironment

struct DerivedDataLocationTests {
    @Test func classify_returns_default_when_value_is_missing() {
        #expect(DerivedDataLocation.classify(rawLocation: nil) == .default)
    }

    @Test func classify_returns_default_when_value_is_empty() {
        #expect(DerivedDataLocation.classify(rawLocation: "") == .default)
    }

    @Test func classify_returns_custom_for_an_absolute_path() throws {
        let result = DerivedDataLocation.classify(rawLocation: "/Users/me/DerivedData")

        #expect(result == .custom(try AbsolutePath(validating: "/Users/me/DerivedData")))
    }

    @Test func classify_returns_relative_for_a_relative_path() throws {
        let result = DerivedDataLocation.classify(rawLocation: ".derived-data")

        #expect(result == .relativeToWorkspace(try RelativePath(validating: ".derived-data")))
    }
}
