import Foundation
import Testing
@testable import SwifterPMCore

struct GitConfigurationTests {
    /// `git config -z` emits one NUL-terminated record per entry, with the key and value
    /// separated by a newline and the value omitted entirely when the key has none.
    private func parse(_ records: [String]) -> GitConfiguration {
        GitConfiguration.parse(records.map { $0 + "\0" }.joined())
    }

    @Test
    func readsUnscopedAndScopedHelpers() {
        let configuration = parse([
            "credential.helper\nosxkeychain",
            "credential.https://github.com.helper\n!gh auth git-credential",
        ])

        #expect(configuration.canAuthenticate("https://anything.example.com/acme/lib.git"))
    }

    @Test
    func aValuelessHelperResetsRatherThanConfigures() {
        // `credential.<url>.helper=` clears the inherited list. Treating it as a configured
        // helper would claim git can authenticate a host nothing is set up for.
        let configuration = parse([
            "credential.https://github.com.helper",
            "credential.https://github.com.helper\n",
        ])

        #expect(!configuration.canAuthenticate("https://github.com/acme/lib.git"))
    }

    @Test
    func scopedHelpersOnlyAnswerForTheirOwnHostAndProtocol() {
        let configuration = parse(["credential.https://github.com.helper\n!gh auth git-credential"])

        #expect(configuration.canAuthenticate("https://github.com/acme/lib.git"))
        #expect(!configuration.canAuthenticate("https://gitlab.com/acme/lib.git"))
        #expect(!configuration.canAuthenticate("http://github.com/acme/lib.git"))
    }

    @Test
    func scopedHelpersHonourTheLeadingWildcard() {
        let configuration = parse(["credential.https://*.example.com.helper\nstore"])

        #expect(configuration.canAuthenticate("https://git.example.com/acme/lib.git"))
        #expect(!configuration.canAuthenticate("https://example.org/acme/lib.git"))
    }

    @Test
    func scopedHelpersAreNotRuledOutByThePath() {
        // `credential.<url>` only considers the path under credential.useHttpPath, and
        // getting that wrong in the "no match" direction would silently demote the attempt
        // that actually works. Match on host and protocol only.
        let configuration = parse(["credential.https://github.com/acme.helper\nstore"])

        #expect(configuration.canAuthenticate("https://github.com/other/lib.git"))
    }

    @Test
    func insteadOfRulesMatchAsLiteralPrefixes() {
        // Git performs no URL parsing here at all: the configured value is compared against
        // the location as a string, longest match winning.
        let configuration = parse([
            "url.https://token@github.com/.insteadof\nhttps://github.com/",
        ])

        #expect(configuration.canAuthenticate("https://github.com/acme/lib.git"))
        #expect(!configuration.canAuthenticate("https://gitlab.com/acme/lib.git"))
        #expect(!configuration.canAuthenticate("https://alice:pw@github.com/acme/lib.git"))
    }

    @Test
    func anEmptyConfigurationAuthenticatesNothing() {
        #expect(!GitConfiguration.empty.canAuthenticate("https://github.com/acme/lib.git"))
    }

    @Test
    func unrelatedKeysAreIgnored() {
        let configuration = parse([
            "credential.usehttppath\ntrue",
            "url.https://github.com/.pushinsteadof\ngit@github.com:",
        ])

        #expect(!configuration.canAuthenticate("https://github.com/acme/lib.git"))
    }
}
