import Testing
import TSCUtility
@testable import TuistSupport

struct TSCUtilityVersionTests {
    @Test
    func version_when_allTagsPresent() {
        #expect(Version(unformattedString: "11.2.3") == Version(11, 2, 3))
    }

    @Test
    func version_when_moreTagsPresent() {
        #expect(Version(unformattedString: "11.2.3.3") == nil)
    }

    @Test
    func version_when_noTagsPresent() {
        #expect(Version(unformattedString: ".") == nil)
    }

    @Test
    func version_when_patchTagOmitted() {
        #expect(Version(unformattedString: "11.2") == Version(11, 2, 0))
    }

    @Test
    func version_when_minorTagOmitted() {
        #expect(Version(unformattedString: "11") == Version(11, 0, 0))
    }

    @Test
    func xcode_string_value() {
        // Given
        let subject = Version(12, 5, 1)

        // When
        let got = subject.xcodeStringValue

        // Then
        #expect(got == "1251")
    }
}
