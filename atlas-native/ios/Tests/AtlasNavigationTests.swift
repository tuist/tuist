import Foundation
import Testing

struct AtlasNavigationTests {
    private let server = URL(string: "https://atlas.example.org")!
    private let recordID = "123e4567-e89b-12d3-a456-426614174000"

    @Test func capabilitiesComeFromRustAndRoundTrip() throws {
        let capabilities = AtlasCore.destinations()
        #expect(capabilities.count == 6)
        for (screen, acceptsRecords) in capabilities {
            let page = try #require(AtlasDestination(screen: screen, server: server))
            #expect(AtlasDestination(url: page.url) == page)
            let record = AtlasDestination(screen: screen, recordID: recordID, server: server)
            #expect((record != nil) == acceptsRecords)
            if let record { #expect(AtlasDestination(url: record.url) == record) }
        }
    }

    @Test func webLinksRoundTripForEveryNativeCapability() throws {
        for (screen, acceptsRecords) in AtlasCore.destinations() {
            let page = try #require(AtlasDestination(screen: screen, server: server))
            #expect(AtlasDestination(url: page.webURL) == page)
            #expect(AtlasDestination(url: URL(string: "https://atlas.example.org/open/\(screen)")!) == page)
            if acceptsRecords {
                let record = try #require(AtlasDestination(screen: screen, recordID: recordID, server: server))
                #expect(AtlasDestination(url: record.webURL) == record)
                #expect(AtlasDestination(url: URL(string: "https://atlas.example.org/open/\(screen)/\(recordID)")!) == record)
                let browser = screen == "accounts" ? URL(string: "https://atlas.example.org/commercial/sales/accounts/\(recordID)")!
                    : page.browserURL
                #expect(record.browserURL == browser)
                if screen == "accounts" { #expect(AtlasDestination(url: record.browserURL) == record) }
            }
            #expect(AtlasDestination(url: page.browserURL) == page)
        }
    }

    @Test func webLinksNeverInterpretQueryOrFragmentAsCredentialsOrServerOverrides() throws {
        let url = try #require(URL(string: "https://ATLAS.example.org:443/tasks?token=secret&server=https://evil.example#delete"))
        let destination = try #require(AtlasDestination(url: url))
        #expect(destination == AtlasDestination(screen: "tasks", server: server))
        #expect(destination.webURL.absoluteString == "https://atlas.example.org/open/tasks")
        #expect(!destination.url.absoluteString.contains("secret"))
    }

    @Test func rejectsUnsupportedWebRoutesAndAmbiguousPaths() throws {
        let paths = ["/", "/tasks/", "/tasks/\(recordID)", "/tasks/new", "/settings/ai-providers",
                     "/auth/login", "/open/people/\(recordID)", "/open/tasks/not-a-uuid", "/open/tasks/\(recordID)/edit",
                     "/commercial/sales/accounts/new", "/commercial/sales/accounts/\(recordID)/notes",
                     "/%74asks", "//tasks", "/open/tasks/%2e%2e", "/open/tasks/123E4567-E89B-12D3-A456-426614174000"]
        for path in paths {
            #expect(AtlasDestination(url: URL(string: "https://atlas.example.org" + path)!) == nil, "Accepted: \(path)")
        }
        for address in ["https:///tasks", "http://atlas.example.org/tasks", "https://user:password@atlas.example.org/tasks",
                        "https://atlas.example.org:0/tasks", "https://atlas.example.org:65536/tasks"] {
            #expect(AtlasDestination(url: URL(string: address)!) == nil)
        }
    }

    @Test func rejectsMalformedAndUntrustedLinks() throws {
        let suffix = "?server=https%3A%2F%2Fatlas.example.org"
        let prefix = "dev.tuist.atlas://navigate/"
        let invalid = [
            "tasks/", "tasks//\(recordID)", "tasks/\(recordID)/edit", "tasks/not-a-uuid", "tasks/1-1-1-1-1",
            "tasks/123E4567-E89B-12D3-A456-426614174000", "people/\(recordID)", "time-off/\(recordID)",
            "profile/\(recordID)", "browser", "notes", "ai-providers", "../tasks", "%74asks", "tasks/%2e%2e"
        ].map { prefix + $0 + suffix } + [
            prefix + "tasks", prefix + "tasks" + suffix + "&server=https://atlas.example.org",
            prefix + "tasks" + suffix + "&action=delete", prefix + "tasks" + suffix + "#fragment",
            "dev.tuist.atlas://user@navigate/tasks" + suffix, "dev.tuist.atlas://navigate:443/tasks" + suffix,
            "dev.tuist.atlas://oauth-callback/tasks" + suffix,
            prefix + "tasks?server=http://atlas.example.org", prefix + "tasks?server=https://user@atlas.example.org",
            prefix + "tasks?server=https://atlas.example.org/other", prefix + "tasks?server=https://atlas.example.org%3Fx=1",
            prefix + "tasks?server=https://atlas.example.org%23fragment", prefix + "tasks?server=https://atlas.example.org:0",
            prefix + "tasks?server=https://éxample.org", prefix + "tasks?server=https://atlas+example.org",
            prefix + "tasks?%73erver=https://atlas.example.org"
        ]
        for value in invalid {
            let url = try #require(URL(string: value))
            #expect(AtlasDestination(url: url) == nil, "Accepted: \(value)")
        }
    }

    @Test func bindsToCanonicalHTTPSOrigin() throws {
        let destination = try #require(AtlasDestination(screen: "tasks", server: URL(string: "https://ATLAS.example.org:443/")!))
        #expect(destination.matches(server))
        #expect(!destination.matches(URL(string: "https://other.example.org")!))
        #expect(!destination.matches(URL(string: "https://atlas.example.org:4443")!))
        #expect(!destination.matches(URL(string: "http://atlas.example.org")!))
        let customPort = try #require(AtlasDestination(screen: "tasks", server: URL(string: "https://atlas.example.org:4443")!))
        #expect(customPort.matches(URL(string: "https://atlas.example.org:4443/")!))
        let ipv6 = try #require(AtlasDestination(screen: "tasks", server: URL(string: "https://[::1]:4443")!))
        #expect(ipv6.matches(URL(string: "https://[::1]:4443/")!))
        #expect(AtlasDestination(url: ipv6.url) == ipv6)
        for address in ["https://xn--xample-9ua.org", "https://xn--xample-9ua.org:4443", "https://atlas_example.org"] {
            let destination = try #require(AtlasDestination(screen: "tasks", server: URL(string: address)!))
            #expect(AtlasDestination(url: destination.url) == destination)
            #expect(destination.matches(URL(string: address)!))
        }
    }

    @MainActor @Test func pendingLatestLinkResolvesOnlyAfterMatchingSignIn() throws {
        let navigation = AtlasNavigation()
        let task = try #require(AtlasDestination(screen: "tasks", recordID: recordID, server: server))
        let account = try #require(AtlasDestination(screen: "accounts", recordID: recordID, server: server))
        navigation.receive(task.webURL, server: nil)
        #expect(navigation.destination == nil)
        navigation.receive(account.webURL, server: nil)
        navigation.resolve(server: server)
        #expect(navigation.destination == account)
        #expect(navigation.selection == "accounts")
        #expect(navigation.pending == nil)
        let accountRevision = navigation.revisions["accounts"]
        navigation.open(task, server: server)
        #expect(navigation.revisions["accounts"] == accountRevision)
        #expect(navigation.destinations["accounts"] == account)
        #expect(navigation.destinations["browse"] == task)
        #expect(navigation.selection == "browse")
        navigation.open(account, server: server)
        let revision = navigation.revision
        navigation.resolve(server: server)
        #expect(navigation.revision == revision)
        navigation.open(task, server: URL(string: "https://other.example.org")!)
        #expect(navigation.destination == account)
        #expect(navigation.message != nil)
        #expect(navigation.pending == nil)
    }

    @MainActor @Test func protectsDraftsAndClearsPendingOnSessionEnd() throws {
        let navigation = AtlasNavigation()
        let destination = try #require(AtlasDestination(screen: "time-off", server: server))
        let blocker = UUID()
        navigation.block(blocker, active: true)
        navigation.open(destination, server: server)
        #expect(navigation.destination == nil)
        #expect(navigation.message == "Finish or discard your changes, then open the link again.")
        #expect(navigation.pending == nil)
        navigation.block(blocker, active: false)
        navigation.open(destination, server: server)
        #expect(navigation.selection == "browse")
        navigation.open(destination, server: nil)
        navigation.reset()
        navigation.resolve(server: server)
        #expect(navigation.destination == nil)
        #expect(navigation.pending == nil)
        #expect(navigation.selection == "conversations")
    }

    @MainActor @Test func hiddenTabProtectionStillRejectsLinksAndCanShowARootNotice() throws {
        let navigation = AtlasNavigation()
        navigation.selection = "profile"
        let blocker = UUID()
        navigation.block(blocker, active: true, tab: "profile")
        navigation.selection = "tasks"
        #expect(navigation.hasProtectedWork && !navigation.hasVisibleProtectedWork)
        let destination = try #require(AtlasDestination(screen: "profile", server: server))
        navigation.open(destination, server: server)
        #expect(navigation.destination == nil && navigation.message != nil)
        navigation.block(blocker, active: false, tab: "profile")
        navigation.open(destination, server: server)
        #expect(navigation.destination == destination)
    }

    @MainActor @Test func recordLookupDoesNotDependOnListPagesAndRejectsCancelledResults() async throws {
        var actions: [String] = []
        let model = AtlasBusiness(resource: .tasks) { action in
            actions.append(action["action"] as? String ?? "")
            #expect(action["resource"] as? String == "tasks")
            #expect(action["id"] as? String == recordID)
            return Data("""
            {"item":{"id":"\(recordID)","fields":{"title":"Beyond the first page"},"can_edit":false,"can_delete":false}}
            """.utf8)
        }
        let item = try await model.record(id: recordID)
        #expect(item["title"] == "Beyond the first page")
        #expect(actions == ["show"])
        #expect(model.page == nil)

        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Never>?
        let cancelledModel = AtlasBusiness(resource: .tasks) { _ in
            await withCheckedContinuation { finish = $0; started.continuation.yield(()) }
        }
        let lookup = Task { try await cancelledModel.record(id: recordID) }
        for await _ in started.stream { break }
        lookup.cancel()
        finish?.resume(returning: Data("""
        {"item":{"id":"\(recordID)","fields":{},"can_edit":false,"can_delete":false}}
        """.utf8))
        do { _ = try await lookup.value; Issue.record("Cancelled record lookup succeeded") } catch is CancellationError {}
        #expect(cancelledModel.records.isEmpty)
    }

    @MainActor @Test func mismatchedRecordResponseCannotOpenAnotherObject() async {
        let model = AtlasBusiness(resource: .tasks) { _ in
            Data("""
            {"item":{"id":"00000000-0000-0000-0000-000000000000","fields":{},"can_edit":true,"can_delete":true}}
            """.utf8)
        }
        do { _ = try await model.record(id: recordID); Issue.record("Accepted a different record") } catch {
            #expect((error as? AtlasAuthenticationError)?.kind == "invalid_response")
        }
        #expect(model.records.isEmpty)
    }

    @MainActor @Test func oauthCallbacksNeverBecomeWorkspaceDestinations() {
        let navigation = AtlasNavigation()
        navigation.receive(URL(string: "dev.tuist.atlas://oauth-callback?code=secret&state=secret")!, server: server)
        #expect(navigation.message == nil)
        #expect(navigation.pending == nil)
    }
}
