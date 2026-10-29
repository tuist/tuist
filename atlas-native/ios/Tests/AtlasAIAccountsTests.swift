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
            if request["action"] as? String == "cancel_chatgpt" {
                cancelled = request["login_id"] as? String
                return Data("{\"status\":\"cancelled\"}".utf8)
            }
            return metadata
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

    @Test func cancellationRefreshesCredentialsAfterAPollWonTheRace() async {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Never>?
        var configured = false
        let accounts = AtlasAIAccounts { request in
            switch request["action"] as? String {
            case "start_chatgpt": return login
            case "poll_chatgpt":
                configured = true
                return await withCheckedContinuation { continuation in
                    finish = continuation
                    started.continuation.yield(())
                }
            case "cancel_chatgpt": throw AtlasAuthenticationError(kind: "login_expired", message: "Expired")
            default:
                return Data("""
                {"providers":[{"provider":"chatgpt","credential_configured":\(configured),"login_available":true}]}
                """.utf8)
            }
        }
        await accounts.startChatGPT()
        let poll = Task { await accounts.poll() }
        for await _ in started.stream { break }
        await accounts.cancelLogin()
        finish?.resume(returning: Data("{\"status\":\"connected\"}".utf8))
        await poll.value
        #expect(accounts.account("chatgpt")?.credentialConfigured == true)
        #expect(accounts.login == nil && accounts.errorMessage == nil && !accounts.busy)
    }

    @Test(arguments: ["login_failed", "rejected"]) func terminalLoginFailureStopsPolling(kind: String) async {
        var polls = 0
        let accounts = AtlasAIAccounts { request in
            if request["action"] as? String == "start_chatgpt" { return login }
            polls += 1
            throw AtlasAuthenticationError(kind: kind, message: "Sign-in failed")
        }
        await accounts.startChatGPT()
        await accounts.poll()
        #expect(polls == 1 && accounts.login == nil && accounts.errorMessage == "Sign-in failed")
    }

    @Test func failedCancellationCanBeRetriedWithoutLosingItsHandle() async {
        var attempts = 0
        let accounts = AtlasAIAccounts { request in
            switch request["action"] as? String {
            case "start_chatgpt": return login
            case "cancel_chatgpt":
                attempts += 1
                #expect(request["login_id"] as? String == "test-login")
                if attempts == 1 { throw AtlasAuthenticationError(kind: "server", message: "Try again") }
                return Data("{}".utf8)
            default: return metadata
            }
        }
        await accounts.startChatGPT()
        await accounts.cancelLogin()
        #expect(accounts.login == nil && accounts.errorMessage == "Try again")
        await accounts.retry()
        #expect(attempts == 2 && accounts.errorMessage == nil && !accounts.busy)
    }

    @Test func lateCredentialFailureDoesNotLeakIntoAnotherPage() async {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Error>?
        let accounts = AtlasAIAccounts { _ in
            try await withCheckedThrowingContinuation { continuation in
                finish = continuation
                started.continuation.yield(())
            }
        }
        let save = Task { await accounts.saveClaude("preview-only") }
        for await _ in started.stream { break }
        accounts.clearError()
        finish?.resume(throwing: AtlasAuthenticationError(kind: "invalid_token", message: "Paste a Claude token"))
        #expect(await save.value == false)
        #expect(accounts.errorMessage == nil && !accounts.busy)
    }

    @Test func unknownFailuresNeverDisplayRawErrors() async {
        let accounts = AtlasAIAccounts { _ in
            throw NSError(domain: "private", code: 1, userInfo: [NSLocalizedDescriptionKey: "secret-token"])
        }
        await accounts.load()
        #expect(accounts.errorMessage == "Could not read the Atlas response. Try again.")
        #expect(!accounts.busy)
        accounts.clearError()
        #expect(accounts.errorMessage == nil)
    }

    @Test func profileEditorRetainsDraftOnFailureAndSendsOnlyDescription() async throws {
        var fail = true
        let editor = AtlasProfileEditorModel(description: "") { action in
            #expect(action["resource"] as? String == "profile" && action["action"] as? String == "update_profile")
            #expect(Set(action.keys) == ["resource", "action", "description"])
            if fail { throw AtlasAuthenticationError(kind: "server", message: "Try again") }
            return Data("""
            {"server_version":"1.0","user":{"name":"Taylor","email":"taylor@example.org","description":"Role\\nCurious"}}
            """.utf8)
        }
        editor.draft = "Role\nCurious"
        #expect(editor.dirty && editor.valid)
        #expect(await editor.save() == nil)
        #expect(editor.draft == "Role\nCurious" && editor.errorMessage == "Try again" && !editor.saving)
        fail = false
        let profile = try #require(await editor.save())
        #expect(profile.user.description == editor.draft && editor.errorMessage == nil)
        editor.draft = String(repeating: "🦀", count: 4000)
        #expect(editor.valid)
        editor.draft += "a"
        #expect(!editor.valid)
        editor.draft = String(repeating: "e\u{301}", count: 2001)
        #expect(!editor.valid)
        editor.draft = ""
        #expect(editor.valid)
    }

    @Test func profileEditorPreventsDoubleSubmissionAndReadsOlderServerProfiles() async throws {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Never>?
        let editor = AtlasProfileEditorModel(description: "Draft") { _ in
            await withCheckedContinuation { finish = $0; started.continuation.yield(()) }
        }
        let save = Task { await editor.save() }
        for await _ in started.stream { break }
        #expect(editor.saving)
        #expect(await editor.save() == nil)
        finish?.resume(returning: Data("""
        {"server_version":"1.0","user":{"name":"Taylor","email":"taylor@example.org"}}
        """.utf8))
        let profile = try #require(await save.value)
        #expect(profile.user.description.isEmpty && !editor.saving)
    }
}
