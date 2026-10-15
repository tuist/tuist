import Foundation
import Testing

@MainActor
struct AtlasAIAccountsTests {
    private let metadata = Data("""
    {"providers":[{"provider":"claude","credential_configured":true,"login_available":true},
    {"provider":"chatgpt","credential_configured":false,"login_available":true}]}
    """.utf8)
    private let login = Data("""
    {"login_id":"test-login","user_code":"EXAMPLE-CODE","verification_url":"https://auth.openai.com/codex/device",
    "interval":0,"expires_at":"2026-10-15T16:00:00Z"}
    """.utf8)

    @Test func loadsMetadataAndSavesClaudeThroughAPI() async {
        var actions: [String] = []
        let accounts = AtlasAIAccounts { request in
            let action = request["action"] as? String ?? ""
            actions.append(action)
            if action == "connect_claude" { #expect(request["token"] as? String == "example-subscription-token") }
            return action == "list" ? metadata : Data("{}".utf8)
        }
        await accounts.load()
        #expect(accounts.account("claude")?.credentialConfigured == true)
        #expect(await accounts.saveClaude("example-subscription-token"))
        #expect(actions == ["list", "connect_claude", "list"])
        #expect(!accounts.busy)
    }

    @Test func cancellingAnInflightStartClearsItsEventualLogin() async {
        let started = AsyncStream<Void>.makeStream()
        var release: CheckedContinuation<Data, Never>?
        var cancelled: String?
        let accounts = AtlasAIAccounts { request in
            if request["action"] as? String == "start_chatgpt" {
                return await withCheckedContinuation { continuation in
                    release = continuation
                    started.continuation.yield(())
                }
            }
            cancelled = request["login_id"] as? String
            return Data("{\"status\":\"cancelled\"}".utf8)
        }
        let start = Task { await accounts.startChatGPT() }
        for await _ in started.stream { break }
        await accounts.cancelLogin()
        release?.resume(returning: login)
        await start.value
        #expect(cancelled == "test-login")
        #expect(accounts.login == nil)
        #expect(!accounts.busy)
    }

    @Test func successfulAuthorizationRefreshesMetadataWithoutExposingTokens() async {
        var actions: [String] = []
        let accounts = AtlasAIAccounts { request in
            let action = request["action"] as? String ?? ""
            actions.append(action)
            switch action {
            case "start_chatgpt": return login
            case "poll_chatgpt": return Data("{\"status\":\"connected\"}".utf8)
            default: return metadata
            }
        }
        await accounts.startChatGPT()
        await accounts.poll()
        #expect(accounts.login == nil)
        #expect(actions == ["start_chatgpt", "poll_chatgpt", "list"])
        #expect(accounts.accounts.count == 2)
    }

    @Test func cancellingPreservesSavedConnectionsAndDisconnectIsExplicit() async {
        var disconnected: String?
        let accounts = AtlasAIAccounts { request in
            switch request["action"] as? String {
            case "start_chatgpt": return login
            case "list": return metadata
            case "disconnect": disconnected = request["provider"] as? String
            default: break
            }
            return Data("{}".utf8)
        }
        await accounts.load()
        await accounts.startChatGPT()
        await accounts.cancelLogin()
        #expect(accounts.account("claude")?.credentialConfigured == true)
        #expect(disconnected == nil)
        await accounts.disconnect("claude")
        #expect(disconnected == "claude")
    }

    @Test func unknownFailuresNeverDisplayRawErrors() async {
        let accounts = AtlasAIAccounts { _ in
            throw NSError(domain: "private", code: 1, userInfo: [NSLocalizedDescriptionKey: "secret-token"])
        }
        await accounts.load()
        #expect(accounts.errorMessage == "Could not read the Atlas response. Try again.")
        #expect(!accounts.busy)
    }
}
