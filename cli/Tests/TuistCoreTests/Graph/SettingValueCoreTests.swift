import Testing
import XcodeGraph

@testable import TuistCore

struct SettingValueCoreTests {
    @Test func quoted_keepsAnItemWithWhitespaceWholeAndEscapesQuotesAndBackslashes() {
        #expect(SettingValue.quoted("/Users/ci/My Projects/app=/root") == #""/Users/ci/My Projects/app=/root""#)
        #expect(SettingValue.quoted(#"say \"hi\""#) == #""say \\\"hi\\\"""#)
        #expect(SettingValue.quoted("plain") == #""plain""#)
    }
}
