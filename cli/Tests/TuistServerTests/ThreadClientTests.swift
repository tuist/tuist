#if DEBUG
    import Foundation
    import Testing
    import TuistHTTP
    @testable import TuistServer

    struct ThreadClientTests {
        private let origin = URL(string: "https://self-hosted.example/prefix")!
        private let catalog = Data(#"{"models":[],"errors":[]}"#.utf8)

        @Test(arguments: ["threads", "jams"])
        func decodesBothPageDialects(key: String) async throws {
            let data = try JSONSerialization.data(withJSONObject: [
                key: JSONSerialization.jsonObject(with: JSONEncoder().encode([thread()])),
                "next_cursor": "opaque+/=",
            ])
            let recorder = Recorder(response: data, queued: key == "jams" ? [(Data(), 404)] : [])
            let page = try await client(recorder).threads(cursor: "cursor+/=")
            #expect(page.threads == [thread()])
            #expect(page.nextCursor == "opaque+/=")
            let requests = await recorder.requests
            #expect(requests.map { $0.url!.path } == (key == "jams"
                    ? ["/prefix/api/accounts/acme/threads", "/prefix/api/accounts/acme/jams"]
                    : ["/prefix/api/accounts/acme/threads"]))
            for request in requests {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
                #expect(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems == [
                    URLQueryItem(name: "cursor", value: "cursor+/="),
                ])
            }
        }

        @Test(arguments: [
            #"{}"#, #"{"threads":null}"#, #"{"jams":{}}"#, #"{"threads":[{}]}"#,
            #"{"threads":null,"jams":[]}"#, #"{"threads":[],"next_cursor":42}"#,
        ])
        func malformedPagesFailWithoutFallback(json: String) async throws {
            let recorder = Recorder(response: Data(json.utf8))
            await #expect(throws: DecodingError.self) { try await client(recorder).threads() }
            #expect(await recorder.requests.count == 1)
        }

        @Test func legacyReadsPreserveHistoryAndDiscoveryContracts() async throws {
            let recorder = Recorder(response: try JSONEncoder().encode(thread()), queued: [(Data(), 404)])
            let client = client(recorder)
            #expect(try await client.thread(id: "thread", before: 51) == thread())
            await recorder.respond(Data(#"{"repositories":[]}"#.utf8), queued: [(Data(), 404)])
            #expect(try await client.repositories().isEmpty)
            await recorder.respond(catalog, queued: [(Data(), 404)])
            #expect(try await client.models().models.isEmpty)
            let requests = await recorder.requests
            #expect(requests.map { $0.url!.path } == [
                "/prefix/api/accounts/acme/threads/thread", "/prefix/api/accounts/acme/jams/thread",
                "/prefix/api/accounts/acme/threads/repositories", "/prefix/api/accounts/acme/jams/repositories",
                "/prefix/api/accounts/acme/threads/models", "/prefix/api/accounts/acme/jams/models",
            ])
            #expect(requests[1].url?.query == "before=51")
        }

        @Test(arguments: [false, true])
        func malformedNegotiationNeverAuthorizesWritesOrSockets(legacy: Bool) async throws {
            let recorder = Recorder(response: Data(#"{}"#.utf8))
            let client = client(recorder)
            for socket in [false, true] {
                await recorder.respond(Data(#"{}"#.utf8), queued: legacy ? [(Data(), 404)] : [])
                await #expect(throws: DecodingError.self) {
                    if socket { _ = try await client.socketConfiguration(threadID: nil) }
                    else { _ = try await client.send("Once", threadID: "thread", requestID: UUID()) }
                }
            }
            #expect(await recorder.requests.allSatisfy { $0.httpMethod == "GET" })
            #expect(await recorder.requests.count == (legacy ? 4 : 2))
        }

        @Test func negotiationDoesNotPinAClientToAnOutdatedDialect() async throws {
            let recorder = Recorder(response: try JSONEncoder().encode(thread()), queued: [(Data(), 404), (catalog, 200)])
            let client = client(recorder)
            _ = try await client.archive(id: "thread", archived: true)
            await recorder.respond(try JSONEncoder().encode(thread()), queued: [(catalog, 200)])
            _ = try await client.archive(id: "thread", archived: false)
            #expect(await recorder.requests.filter { $0.httpMethod == "PATCH" }.map { $0.url!.path } == [
                "/prefix/api/accounts/acme/jams/thread", "/prefix/api/accounts/acme/threads/thread",
            ])
        }

        @Test(arguments: [false, true])
        func mutationsNegotiateBeforeEveryWrite(legacy: Bool) async throws {
            let recorder = Recorder(response: try JSONEncoder().encode(thread()))
            let client = client(recorder)
            let prefix = "/prefix/api/accounts/acme/"
            let route = legacy ? "jams" : "threads"
            for operation in 0 ..< 5 {
                let responses = (legacy ? [(Data(), 404)] : []) + [(catalog, 200)]
                let preview = ThreadShipPreview(
                    headSHA: "head", baseSHA: "base", diff: "patch", targetBranch: "main", mode: "branch", requestID: UUID()
                )
                let previewData = Data("""
                {"head_sha":"head","base_sha":"base","diff":"patch","target_branch":"main",
                "mode":"branch","request_id":"\(preview.requestID)"}
                """.utf8)
                await recorder.respond(operation == 3 ? previewData : try JSONEncoder().encode(thread()), queued: responses)
                switch operation {
                case 0:
                    _ = try await client.create(
                        content: "New",
                        repository: nil,
                        provider: "claude",
                        model: "m",
                        requestID: UUID()
                    )
                case 1: _ = try await client.send("Next", threadID: "thread", requestID: UUID())
                case 2: _ = try await client.archive(id: "thread", archived: true)
                case 3: _ = try await client.shipPreview(id: "thread")
                default: _ = try await client.ship(id: "thread", approval: preview)
                }
            }
            let requests = await recorder.requests
            let suffixes = ["", "/thread/messages", "/thread", "/thread/ship-preview", "/thread/ship"]
            #expect(requests.filter { $0.httpMethod != "GET" }.map { $0.url!.path } == suffixes.map { prefix + route + $0 })
            let expectedMethods = (0 ..< 5).flatMap { operation in
                (legacy ? ["GET", "GET"] : ["GET"]) + [operation == 2 ? "PATCH" : "POST"]
            }
            let expectedDiscoveryPaths = (0 ..< 5).flatMap { _ in
                legacy ? [prefix + "threads/models", prefix + "jams/models"] : [prefix + "threads/models"]
            }
            #expect(requests.map { $0.httpMethod! } == expectedMethods)
            #expect(requests.filter { $0.httpMethod == "GET" }.map { $0.url!.path } == expectedDiscoveryPaths)
        }

        @Test(arguments: [401, 403, 409, 500, 503])
        func rejectedReadsAndNegotiationNeverChangeDialect(status: Int) async throws {
            for operation in 0 ..< 3 {
                let recorder = Recorder(response: Data(), status: status)
                let client = client(recorder)
                await #expect(throws: ThreadClientError.self) {
                    switch operation {
                    case 0: _ = try await client.threads()
                    case 1: _ = try await client.archive(id: "thread", archived: true)
                    default: _ = try await client.socketConfiguration(threadID: nil)
                    }
                }
                let requests = await recorder.requests
                #expect(!requests.isEmpty)
                #expect(requests.allSatisfy { $0.httpMethod == "GET" && !$0.url!.path.contains("jams") })
                if status < 500 { #expect(requests.count == 1) }
            }
        }

        @Test(arguments: [404, 401, 403, 409, 500, 503])
        func failedWritesNeverReplayOrChangeDialect(status: Int) async throws {
            for legacy in [false, true] {
                let recorder = Recorder(
                    response: Data(), status: status,
                    queued: (legacy ? [(Data(), 404)] : []) + [(catalog, 200)]
                )
                await #expect(throws: ThreadClientError.self) {
                    try await client(recorder).archive(id: "thread", archived: true)
                }
                let writes = await recorder.requests.filter { $0.httpMethod != "GET" }
                #expect(writes.count == 1)
                #expect(writes.first?.url?.path == "/prefix/api/accounts/acme/\(legacy ? "jams" : "threads")/thread")
            }
        }

        @Test(arguments: [false, true], [nil, "thread"] as [String?])
        func socketsNegotiateMatchingPathAndTopicWithoutLeakingCredentials(legacy: Bool, threadID: String?) async throws {
            let recorder = Recorder(response: catalog, queued: legacy ? [(Data(), 404)] : [])
            let (request, topic) = try await client(recorder).socketConfiguration(threadID: threadID)
            let route = legacy ? "jams" : "threads"
            #expect(request.url?.absoluteString == "wss://self-hosted.example/prefix/\(route)/socket/websocket?vsn=2.0.0")
            #expect(topic == "\(route):acme:\(threadID ?? "inbox")")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Sec-WebSocket-Protocol") == "phoenix, base64url.bearer.phx.dGVzdC1vbmx5")
            #expect(await recorder.requests.count == (legacy ? 2 : 1))
        }

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
            let recorder = Recorder(response: try JSONEncoder().encode(thread()), queued: [(catalog, 200)])
            let id = UUID()
            let result = try await client(recorder).create(
                content: "Explain the architecture", repository: nil, provider: "claude", model: "model-id", requestID: id
            )
            #expect(result.provider == "claude")
            #expect(result.model == "model-id")
            let request = try #require(await recorder.requests.last)
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
            await recorder.respond(try JSONEncoder().encode(thread()), queued: [(catalog, 200)])
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
            let data = try JSONEncoder().encode(thread())
            let recorder = Recorder(response: data, queued: [(data, 200), (catalog, 200), (data, 200), (catalog, 200)])
            let client = client(recorder)
            _ = try await client.thread(id: "thread", before: 51)
            _ = try await client.send("Continue", threadID: "thread", requestID: UUID())
            _ = try await client.archive(id: "thread", archived: true)
            let requests = await recorder.requests.filter { $0.url?.lastPathComponent != "models" }
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
            let recorder = Recorder(response: Data(json.utf8), queued: [(catalog, 200)])
            let client = client(recorder)
            let preview = try await client.shipPreview(id: "thread")
            #expect(await recorder.requests.count == 2)
            #expect(await recorder.requests.last?.url?.lastPathComponent == "ship-preview")
            await recorder.respond(try JSONEncoder().encode(thread()), queued: [(catalog, 200)])
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
            let recorder = Recorder(response: Data(), status: 503, queued: [(catalog, 200)])
            await #expect(throws: ThreadClientError.self) {
                try await client(recorder).send("Once", threadID: "thread", requestID: UUID())
            }
            #expect(await recorder.requests.filter { $0.httpMethod == "POST" }.count == 1)
        }

        @Test func lostWriteResponseIsNotReplayed() async throws {
            let recorder = Recorder(response: Data(), queued: [(catalog, 200)], failure: URLError(.networkConnectionLost))
            await #expect(throws: URLError.self) {
                try await client(recorder).send("Once", threadID: "thread", requestID: UUID())
            }
            #expect(await recorder.requests.map(\.httpMethod) == ["GET", "POST"])
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
            var queued: [(Data, Int)]
            let failure: URLError?

            init(response: Data, status: Int = 200, queued: [(Data, Int)] = [], failure: URLError? = nil) {
                self.response = response
                self.status = status
                self.queued = queued
                self.failure = failure
            }

            func respond(_ data: Data, queued: [(Data, Int)] = []) {
                response = data
                self.queued = queued
            }

            func perform(_ request: URLRequest) throws -> (Data, URLResponse) {
                requests.append(request)
                let data: Data
                let code: Int
                if !queued.isEmpty {
                    (data, code) = queued.removeFirst()
                } else if let failure {
                    throw failure
                } else {
                    (data, code) = (response, status)
                }
                return (data, HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
            }
        }
    }
#endif
