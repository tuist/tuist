import Testing
@testable import TuistSupport

struct StringRegexTests {
    @Test
    func string_regex() {
        let osVersionPattern = "\\b[0-9]+\\.[0-9]+(?:\\.[0-9]+)?\\b"
        #expect("10.0.1".matches(pattern: osVersionPattern))
        #expect(!"tuist".matches(pattern: osVersionPattern))

        let twoDigitsOnlyPattern = "^[0-9]{2}$"
        #expect("10".matches(pattern: twoDigitsOnlyPattern))
        #expect(!"10.0.1".matches(pattern: twoDigitsOnlyPattern))

        let singleWordPattern = "project*"
        #expect("project".matches(pattern: singleWordPattern))
        #expect(!"This is a project".matches(pattern: singleWordPattern))
    }
}
