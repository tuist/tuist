import Foundation
import Testing

@MainActor
struct AtlasConnectionsTests {
    private func metadata(_ status: String) -> Data {
        Data("""
        {"connections":[{"provider":"github","name":"GitHub","configured":true,
        "account_name":"demo-developer","status":"\(status)"}]}
        """.utf8)
    }

    @Test func cachedConnectionMustRefreshBeforeDisconnectAndDenialClearsIt() async {
        var failure: String? = "network"
        var status = "connected"
        let model = AtlasConnections(request: { action in
            if action["action"] as? String == "disconnect" { status = "not_connected"; return Data("{}".utf8) }
            if let failure { throw AtlasAuthenticationError(kind: failure, message: "Unavailable") }
            return metadata(status)
        }, authorize: { _ in nil })
        model.cachedRequest = { _ in metadata("connected") }
        await model.load()
        #expect(model.cached && model.connections.first?.connected == true)
        failure = nil
        await model.disconnect("github")
        #expect(model.cached && model.connections.first?.connected == true)
        await model.load()
        #expect(!model.cached && model.connections.first?.connected == true)
        failure = "sign_in_required"
        await model.load()
        #expect(model.connections.isEmpty && !model.busy)
    }

    @Test func browserReturnReloadsTheAuthoritativeGrantInsteadOfTrustingTheURL() async {
        for status in ["connected", "not_connected"] {
            let model = AtlasConnections(request: { action in
                switch action["action"] as? String {
                case "begin": return Data("""
                    {"authorization_url":"https://atlas.example.org/connections/github/authorize?native=demo","pending":{}}
                    """.utf8)
                case "complete": return Data("{\"provider\":\"github\",\"status\":\"connected\"}".utf8)
                default: return metadata(status)
                }
            }, authorize: { _ in URL(string: "dev.tuist.atlas://connections-callback?preview-only") })
            await model.connect("github")
            #expect(model.connections.first?.status == status)
            #expect((model.message == nil) == (status == "connected"))
            #expect(!model.busy)
        }
    }

    @Test func browserCancellationLeavesTheConnectionAvailableForRetry() async {
        let model = AtlasConnections(request: { action in
            if action["action"] as? String == "begin" {
                return Data("""
                {"authorization_url":"https://atlas.example.org/connections/github/authorize?native=demo","pending":{}}
                """.utf8)
            }
            return metadata("connected")
        }, authorize: { _ in nil })
        await model.load()
        await model.connect("github")
        #expect(model.message == "Connection cancelled.")
        #expect(model.connections.first?.status == "connected")
        #expect(!model.busy)
    }

    @Test func signingOutWhileBrowserIsOpenDiscardsTheReturn() async {
        var browser: CheckedContinuation<URL?, Never>?
        let model = AtlasConnections(request: { action in
            if action["action"] as? String == "begin" {
                return Data("""
                {"authorization_url":"https://atlas.example.org/connections/github/authorize?native=demo","pending":{}}
                """.utf8)
            }
            return metadata("connected")
        }, authorize: { _ in await withCheckedContinuation { browser = $0 } })
        let task = Task { await model.connect("github") }
        while browser == nil { await Task.yield() }
        model.invalidate()
        browser?.resume(returning: URL(string: "dev.tuist.atlas://connections-callback?preview-only"))
        await task.value
        #expect(model.connections.isEmpty && model.message == nil && !model.busy)
    }
}
