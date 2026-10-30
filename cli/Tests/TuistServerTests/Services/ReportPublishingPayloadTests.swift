#if canImport(TuistXCActivityLog) && canImport(TuistXCResultService)
    import Foundation
    import HTTPTypes
    import Mockable
    import OpenAPIRuntime
    import Testing
    import TuistEnvironment
    import TuistXCResultService
    import XCResultParser

    @testable import TuistServer

    struct ReportPublishingPayloadTests {
        private let serverURL = URL(string: "https://tuist.example")!
        private typealias MakeClient = @Sendable (URL, Bool) -> Client

        @Test(arguments: [true, false])
        func build_payload_and_transport_share_the_discovered_mode(unsigned: Bool) async {
            await withPublishingMode(unsigned: unsigned) { makeClient in
                let service = CreateBuildService(makeClient: makeClient)
                await #expect(throws: CreateBuildServiceError.self) {
                    try await service.createBuild(
                        fullHandle: "acme/app", serverURL: serverURL, id: "build-id", generationId: "generation-id",
                        category: .incremental, configuration: nil, customMetadata: nil, duration: 1, files: [],
                        gitBranch: nil, gitCommitSHA: nil, gitRef: nil, gitRemoteURLOrigin: "private-origin",
                        isCI: false, issues: [], modelIdentifier: nil, macOSVersion: "15", scheme: nil, targets: [],
                        xcodeCacheUploadEnabled: true, xcodeVersion: nil, status: .success, ciRunId: nil,
                        ciProjectHandle: nil, ciHost: nil, ciProvider: nil, cacheableTasks: [], casOutputs: [], machineMetrics: []
                    )
                }
            }
        }

        @Test(arguments: [true, false])
        func payload_and_transport_share_the_discovered_mode(unsigned: Bool) async {
            await withPublishingMode(unsigned: unsigned) { makeClient in
                let service = CreateTestService(makeClient: makeClient)
                await #expect(throws: CreateTestServiceError.self) {
                    try await service.createTest(
                        fullHandle: "acme/app", serverURL: serverURL,
                        testSummary: TestSummary(testPlanName: nil, status: .passed, duration: 1, testModules: []),
                        buildRunId: "build-id", gitBranch: nil, gitCommitSHA: nil, gitRef: nil,
                        gitRemoteURLOrigin: "private-origin", isCI: false, modelIdentifier: nil, macOSVersion: "15",
                        xcodeVersion: nil, ciRunId: nil, ciProjectHandle: nil, ciHost: nil, ciProvider: nil,
                        shardPlanId: "plan-id", shardIndex: 0, onlyTestIdentifiers: ["Only"], skipTestIdentifiers: ["Skip"]
                    )
                }
            }
        }

        private func withPublishingMode(unsigned: Bool, run: (@escaping MakeClient) async -> Void) async {
            let credentials = MockServerCredentialsStoring()
            given(credentials).read(serverURL: .any).willReturn(nil)
            let environment = Environment(variables: unsigned ? [:] : ["TUIST_TOKEN": "supplied-token"], arguments: [])
            await CachedValueStore.$current.withValue(CachedValueStore(backend: .inSystemProcess)) {
                await Environment.$current.withValue(environment) {
                    await ServerCredentialsStore.$current.withValue(credentials) {
                        await confirmation(
                            "Discover exactly once when credentials are absent",
                            expectedCount: unsigned ? 1 : 0
                        ) { discovered in
                            let discover: @Sendable (URL) async throws -> Bool = { _ in
                                discovered()
                                return true
                            }
                            await ServerReportPublishingMode.$serverAllowsNetworkPublishing.withValue(discover) {
                                await confirmation("Send the report") { sent in
                                    await run { url, networkTrusted in
                                        #expect(networkTrusted == unsigned)
                                        return Client(
                                            serverURL: url,
                                            transport: ReportPayloadTransport(unsigned: unsigned, onSend: { sent() }),
                                            middlewares: [ServerClientAuthenticationMiddleware(
                                                networkTrustedReports: true, networkTrustedPublishing: networkTrusted
                                            )]
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private struct ReportPayloadTransport: ClientTransport {
        let unsigned: Bool
        let onSend: @Sendable () -> Void

        func send(
            _ request: HTTPRequest, body: HTTPBody?, baseURL _: URL, operationID: String
        ) async throws -> (HTTPResponse, HTTPBody?) {
            onSend()
            #expect(request.headerFields[.authorization] == (unsigned ? nil : "Bearer supplied-token"))
            let data = try await Data(collecting: #require(body), upTo: 1_000_000)
            let payload = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(payload["git_remote_url_origin"] as? String == (unsigned ? nil : "private-origin"))
            if operationID == "createBuild" {
                #expect(payload["generation_id"] as? String == (unsigned ? nil : "generation-id"))
                #expect(payload["xcode_cache_upload_enabled"] as? Bool == !unsigned)
            } else {
                #expect(operationID == "createTest")
                #expect(payload["build_run_id"] as? String == (unsigned ? nil : "build-id"))
                #expect(payload["shard_plan_id"] as? String == (unsigned ? nil : "plan-id"))
                #expect(payload["shard_index"] as? Int == (unsigned ? nil : 0))
                #expect((payload["only_test_identifiers"] as? [String] ?? []) == (unsigned ? [] : ["Only"]))
                #expect((payload["skip_test_identifiers"] as? [String] ?? []) == (unsigned ? [] : ["Skip"]))
            }
            var response = HTTPResponse(status: .badRequest)
            response.headerFields[.contentType] = "application/json"
            return (response, HTTPBody(#"{"message":"Captured report"}"#))
        }
    }
#endif
