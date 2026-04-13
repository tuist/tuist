import Foundation
import ProjectDescription
import Testing
import TuistConfig

@testable import TuistLoader

struct ProxyManifestMapperTests {
    @Test func from_none() throws {
        let got = try TuistConfig.Tuist.Proxy.from(manifest: .none)
        #expect(got == .none)
    }

    @Test func from_environmentVariable_defaultsToHTTPS_PROXY() throws {
        let got = try TuistConfig.Tuist.Proxy.from(manifest: .environmentVariable())
        #expect(got == .environmentVariable("HTTPS_PROXY"))
    }

    @Test func from_environmentVariable_withCustomName() throws {
        let got = try TuistConfig.Tuist.Proxy.from(manifest: .environmentVariable("CORP_PROXY"))
        #expect(got == .environmentVariable("CORP_PROXY"))
    }

    @Test func from_url_parsesAndKeepsURL() throws {
        let got = try TuistConfig.Tuist.Proxy.from(manifest: .url("http://proxy.corp:8080"))
        guard case let .url(url) = got else {
            Issue.record("Expected .url, got \(got)")
            return
        }
        #expect(url.absoluteString == "http://proxy.corp:8080")
    }

    @Test func stringLiteral_mapsToUrlCase() throws {
        // `Tuist.Proxy` conforms to `ExpressibleByStringLiteral`, so a bare string
        // literal in `Tuist.swift` maps to `.url(...)`.
        let fromLiteral: ProjectDescription.Tuist.Proxy = "http://proxy.corp:8080"
        #expect(fromLiteral == .url("http://proxy.corp:8080"))
    }

    @Test func from_url_throwsOnInvalidURL() throws {
        // A string containing raw whitespace is rejected by `URL(string:)`, so the
        // mapper surfaces `invalidProxyURL` rather than silently swallowing it.
        #expect(throws: ConfigManifestMapperError.self) {
            _ = try TuistConfig.Tuist.Proxy.from(manifest: .url("http://proxy with spaces"))
        }
    }
}
