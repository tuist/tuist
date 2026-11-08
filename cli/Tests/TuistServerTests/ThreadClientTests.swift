#if DEBUG
    import Foundation
    import Testing
    import TuistHTTP
    @testable import TuistServer

    struct ThreadClientTests {
        private let origin = URL(string: "https://self-hosted.example/prefix")!

        @Test func disjointInboxRefreshRestartsAtTheFreshCursor() {
            let old = (1 ... 25).map { thread(id: "old-\($0)") }
            let new = (1 ... 30).map { thread(id: "new-\($0)") }
            let loaded = ThreadPage(threads: old, nextCursor: nil)
            let fresh = ThreadPage(threads: Array(new.prefix(25)), nextCursor: "fresh")
            let refreshed = loaded.mergingRefresh(fresh)
            #expect(refreshed.threads == fresh.threads)
            #expect(refreshed.nextCursor == "fresh")
        }

        @Test(arguments: [nil, "older"] as [String?])
        func contiguousInboxRefreshPreservesLoadedTailAndCursor(cursor: String?) {
            let old = (1 ... 50).map { thread(id: "old-\($0)") }
            let new = thread(id: "new")
            let loaded = ThreadPage(threads: old, nextCursor: cursor)
            let fresh = ThreadPage(threads: [new] + old.prefix(24), nextCursor: "fresh")
            let refreshed = loaded.mergingRefresh(fresh)
            #expect(refreshed.threads == [new] + old)
            #expect(refreshed.nextCursor == cursor)
            let reordered = [thread(id: "old-2", revision: 2), new, old[0]] + old.dropFirst(2)
            let updated = refreshed.mergingRefresh(ThreadPage(threads: Array(reordered.prefix(25)), nextCursor: "fresh"))
            #expect(updated.threads == reordered)
            #expect(updated.nextCursor == cursor)
        }

        @Test func movedOverlapDoesNotProveInboxContinuity() {
            let old = (1 ... 25).map { thread(id: "old-\($0)") }
            let new = (1 ... 24).map { thread(id: "new-\($0)") }
            let loaded = ThreadPage(threads: old, nextCursor: "old-cursor")
            for overlap in [thread(id: "old-25", revision: 2), thread(id: "old-1", revision: 2), old[24]] {
                let fresh = ThreadPage(threads: new + [overlap], nextCursor: "fresh")
                let refreshed = loaded.mergingRefresh(fresh)
                #expect(refreshed.threads == fresh.threads)
                #expect(refreshed.nextCursor == "fresh")
            }
            let empty = loaded.mergingRefresh(ThreadPage(threads: [], nextCursor: nil))
            #expect(empty.threads.isEmpty)
            #expect(empty.nextCursor == nil)
        }

        @Test func listsWithSelectedOriginBearerAndOpaqueCursor() async throws {
            let recorder = Recorder(response: Data(#"{"threads":[],"next_cursor":"next+/="}"#.utf8))
            let page = try await client(recorder).threads(cursor: "opaque+/=")
            #expect(page.nextCursor == "next+/=")
            let request = try #require(await recorder.requests.first)
            #expect(request.url?.path == "/prefix/api/accounts/acme/threads")
            #expect(request.url?.host == "self-hosted.example")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
            let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
            #expect(query == [URLQueryItem(name: "cursor", value: "opaque+/=")])
        }

        @Test func createsWithoutInventingARepositoryOrEnvironment() async throws {
            let recorder = Recorder(response: try JSONEncoder().encode(thread()))
            let id = UUID()
            let result = try await client(recorder).create(
                content: "Explain the architecture", repository: nil, provider: "claude", model: "model-id", requestID: id
            )
            #expect(result.provider == "claude")
            #expect(result.model == "model-id")
            let request = try #require(await recorder.requests.first)
            let body = try body(request)
            #expect(request.httpMethod == "POST")
            #expect(body["content"] as? String == "Explain the architecture")
            #expect(body["provider"] as? String == "claude")
            #expect(body["model"] as? String == "model-id")
            #expect(body["repository"] is NSNull)
            #expect(body["profile"] == nil)
            #expect(body["base_branch"] == nil)
            #expect(body["request_id"] as? String == id.uuidString.lowercased())
        }

        @Test func discoversRepositoriesAndUsesTheirDefaultBranch() async throws {
            let recorder =
                Recorder(response: Data(#"{"repositories":[{"full_name":"acme/app","default_branch":"develop"}]}"#.utf8))
            let repositories = try await client(recorder).repositories()
            #expect(await recorder.requests.first?.url?.path == "/prefix/api/accounts/acme/threads/repositories")
            await recorder.respond(try JSONEncoder().encode(thread()))
            _ = try await client(recorder).create(
                content: "Fix it", repository: repositories.first, provider: "chatgpt", model: "gpt-id", requestID: UUID()
            )
            let request = try #require(await recorder.requests.last)
            #expect(try body(request)["base_branch"] as? String == "develop")
            #expect(try body(request)["repository"] as? String == "acme/app")
            #expect(try body(request)["provider"] as? String == "chatgpt")
            #expect(try body(request)["model"] as? String == "gpt-id")
        }

        @Test func discoversAuthenticatedModelsAndPreservesPartialProviderErrors() async throws {
            let json = #"{"models":[{"provider":"chatgpt","id":"model-id","name":"Display name"}],"errors":[{"provider":"claude","code":"models_unavailable"}]}"#
            let recorder = Recorder(response: Data(json.utf8))
            let catalog = try await client(recorder).models()
            #expect(catalog.models == [.init(provider: "chatgpt", id: "model-id", name: "Display name")])
            #expect(catalog.errors.first?.provider == "claude")
            #expect(catalog.errors.first?.code == "models_unavailable")
            let request = try #require(await recorder.requests.first)
            #expect(request.url?.absoluteString == "https://self-hosted.example/prefix/api/accounts/acme/threads/models")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
            #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        }

        @Test func emptyModelAccessIsNotReplacedByDefaults() async throws {
            let recorder = Recorder(response: Data(#"{"models":[],"errors":[]}"#.utf8))
            let catalog = try await client(recorder).models()
            #expect(catalog.models.isEmpty)
            #expect(catalog.errors.isEmpty)
            await recorder.respond(Data(#"{"models":[],"errors":[{"provider":"claude","code":"models_unavailable"}]}"#.utf8))
            let unavailable = try await client(recorder).models()
            #expect(unavailable.models.isEmpty)
            #expect(unavailable.errors.count == 1)
        }

        @Test func rejectedModelCatalogIsAnErrorNotEmptyAccess() async throws {
            let recorder = Recorder(response: Data(), status: 403)
            await #expect(throws: ThreadClientError.self) { try await client(recorder).models() }
            #expect(await recorder.requests.count == 1)
        }

        @Test func historyMessageAndArchiveContracts() async throws {
            let recorder = Recorder(response: try JSONEncoder().encode(thread()))
            let client = client(recorder)
            _ = try await client.thread(id: "thread", before: 51)
            _ = try await client.send("Continue", threadID: "thread", requestID: UUID())
            _ = try await client.archive(id: "thread", archived: true)
            let requests = await recorder.requests
            #expect(requests[0].url?.query == "before=51")
            #expect(requests[1].url?.path == "/prefix/api/accounts/acme/threads/thread/messages")
            #expect(try body(requests[1])["content"] as? String == "Continue")
            #expect(try body(requests[1])["provider"] == nil)
            #expect(try body(requests[1])["model"] == nil)
            #expect(requests[2].httpMethod == "PATCH")
            #expect(try body(requests[2])["status"] as? String == "archived")
            #expect(try body(requests[2])["provider"] == nil)
            #expect(try body(requests[2])["model"] == nil)
        }

        @Test func shippingRequiresAnExactReviewedSnapshot() async throws {
            let id = UUID()
            let json = """
            {"head_sha":"head","base_sha":"base","diff":"patch","target_branch":"develop","mode":"branch","request_id":"\(id)"}
            """
            let recorder = Recorder(response: Data(json.utf8))
            let client = client(recorder)
            let preview = try await client.shipPreview(id: "thread")
            #expect(await recorder.requests.count == 1)
            #expect(await recorder.requests.first?.url?.lastPathComponent == "ship-preview")
            await recorder.respond(try JSONEncoder().encode(thread()))
            _ = try await client.ship(id: "thread", approval: preview)
            let request = try #require(await recorder.requests.last)
            let body = try body(request)
            #expect(request.url?.lastPathComponent == "ship")
            #expect(body["head_sha"] as? String == "head")
            #expect(body["base_sha"] as? String == "base")
            #expect(body["target_branch"] as? String == "develop")
            #expect(body["mode"] as? String == "branch")
            #expect(body["request_id"] as? String == id.uuidString.lowercased())
        }

        @Test func ambiguousWritesAreNotAutomaticallyReplayed() async throws {
            let recorder = Recorder(response: Data(), status: 503)
            await #expect(throws: ThreadClientError.self) {
                try await client(recorder).send("Once", threadID: "thread", requestID: UUID())
            }
            #expect(await recorder.requests.count == 1)
        }

        @Test func unauthorizedReadsDoNotRetryOrDecodeAsEmpty() async throws {
            let recorder = Recorder(response: Data(), status: 401)
            await #expect(throws: ThreadClientError.self) { try await client(recorder).threads() }
            #expect(await recorder.requests.count == 1)
        }

        @Test func phoenixFramesUseVersionTwoArrayEncoding() throws {
            let join = try ThreadClient.frame(join: "1", ref: "1", topic: "threads:acme:inbox", event: "phx_join")
            let frame = try #require(JSONSerialization.jsonObject(with: Data(join.utf8)) as? [Any])
            #expect(frame.count == 5)
            #expect(frame[0] as? String == "1")
            #expect(frame[2] as? String == "threads:acme:inbox")
            #expect(frame[3] as? String == "phx_join")
            let heartbeat = try ThreadClient.frame(join: nil, ref: "2", topic: "phoenix", event: "heartbeat")
            let heartbeatFrame = try #require(JSONSerialization.jsonObject(with: Data(heartbeat.utf8)) as? [Any])
            #expect(heartbeatFrame[0] is NSNull)
        }

        @Test func socketAuthenticationUsesSubprotocolNotQueryCredentials() throws {
            let client = client(Recorder(response: Data()))
            let request = client.socketRequest(token: "test-only")
            #expect(request.url?.absoluteString == "wss://self-hosted.example/prefix/threads/socket/websocket?vsn=2.0.0")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "phoenix, base64url.bearer.phx.dGVzdC1vbmx5")
        }

        @Test func olderHistorySurvivesRefreshAndStaleRevisionCannotOverwrite() {
            var current = thread(positions: [51, 52], revision: 4, before: 51)
            current = current.mergingHistory(thread(positions: [49, 50, 51], revision: 3, before: 49), older: true)
            #expect(current.messages.compactMap(\.position) == [49, 50, 51, 52])
            #expect(current.revision == 4)
            #expect(current.nextBefore == 49)
            current = current.mergingHistory(thread(positions: [51, 52, 53], revision: 5, before: 51))
            #expect(current.messages.compactMap(\.position) == [49, 50, 51, 52, 53])
            #expect(current.nextBefore == 49)
            #expect(current.mergingHistory(thread(revision: 1)) == current)
        }

        @Test func paginationResetsWhenReconnectLeavesAGapAndStopsRepeatedCursor() {
            let current = thread(positions: [1, 2], revision: 1, before: 1)
            let page = thread(positions: [100, 101], revision: 2, before: 100)
            #expect(current.mergingHistory(page) == page)
            let repeated = current.mergingHistory(current, older: true)
            #expect(repeated.hasMore == false)
            #expect(repeated.nextBefore == nil)
        }

        @Test func decodesOptionalHistoryAndUnsupportedRichPresentation() throws {
            let json = """
            {"id":"t","title":"Title","goal":"Goal","repository":"","branch":"","profile":"linux",
            "status":"completed","visibility":"private","diff":"","revision":9,"has_more":true,"next_before":4,
            "archive_status":"active","messages":[{"id":"m","role":"assistant","content":"Keep this",
            "position":4,"richContent":{"kind":"future"}}]}
            """
            let decoded = try JSONDecoder().decode(DemoThread.self, from: Data(json.utf8))
            #expect(decoded.nextBefore == 4)
            #expect(decoded.hasMore == true)
            #expect(decoded.revision == 9)
            #expect(decoded.messages.first?.content == "Keep this")
            #expect(decoded.messages.first?.richContent == nil)
        }

        private func client(_ recorder: Recorder) -> ThreadClient {
            ThreadClient(
                account: "acme",
                serverURL: origin,
                session: .tuistDefault,
                token: { "test-only" },
                perform: { try await recorder.perform($0) }
            )
        }

        private func body(_ request: URLRequest) throws -> [String: Any] {
            let data = try #require(request.httpBody)
            return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        }

        private func thread(id: String = "thread", positions: [Int] = [], revision: Int = 1, before: Int? = nil) -> DemoThread {
            var thread = DemoThread(
                id: id,
                title: "Title",
                repository: "",
                profile: "linux",
                status: "completed",
                visibility: "private",
                messages: positions.map {
                    ThreadMessage(id: String($0), role: "assistant", content: "Reply", position: $0)
                }, provider: "claude", model: "model-id"
            )
            thread.revision = revision
            thread.nextBefore = before
            thread.hasMore = before != nil
            return thread
        }

        private actor Recorder {
            var requests: [URLRequest] = []
            var response: Data
            let status: Int

            init(response: Data, status: Int = 200) {
                self.response = response
                self.status = status
            }

            func respond(_ data: Data) { response = data }

            func perform(_ request: URLRequest) throws -> (Data, URLResponse) {
                requests.append(request)
                return (response, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
            }
        }
    }
#endif
