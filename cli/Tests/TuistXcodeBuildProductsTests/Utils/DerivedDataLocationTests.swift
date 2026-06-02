import Path
import Testing
import TuistEnvironment

struct DerivedDataLocationTests {
    @Test func init_returns_default_for_an_empty_value() {
        #expect(DerivedDataLocation("") == .default)
    }

    @Test func init_returns_custom_for_an_absolute_path() throws {
        let result = DerivedDataLocation("/Users/me/DerivedData")

        #expect(result == .custom(try AbsolutePath(validating: "/Users/me/DerivedData")))
    }

    @Test func init_returns_relative_for_a_relative_path() throws {
        let result = DerivedDataLocation(".derived-data")

        #expect(result == .relativeToWorkspace(try RelativePath(validating: ".derived-data")))
    }
}
