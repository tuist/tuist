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

    @Test func from_environmentVariable_withDefaultName() throws {
        let got = try TuistConfig.Tuist.Proxy.from(manifest: .environmentVariable())
        #expect(got == .environmentVariable(nil))
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

}
