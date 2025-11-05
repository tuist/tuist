import Foundation
import GRPCCore
import Mockable
import OpenAPIRuntime
import Testing
import TuistServer
import TuistSupport
import TuistTesting
@testable import TuistCAS
@testable import TuistCASAnalytics

struct KeyValueServiceTests {
    private let subject: KeyValueService
    private let putCacheValueService: MockPutCacheValueServicing
    private let getCacheValueService: MockGetCacheValueServicing
    private let nodeStore: MockCASNodeStoring
    private let fullHandle = "tuist/tuist"
    private let serverURL = URL(string: "https://example.com")!

    init() {
        putCacheValueService = .init()
        getCacheValueService = .init()
        nodeStore = .init()

        subject = KeyValueService(
            fullHandle: fullHandle,
            serverURL: serverURL,
            putCacheValueService: putCacheValueService,
            getCacheValueService: getCacheValueService,
            nodeStore: nodeStore
        )
    }

    @Test
    func putValue_when_successful() async throws {
        // Given
        let key = Data("MH5TRFZyVWpGYU5scEZUWGhqYkhCWllYb3dQUT09".utf8)
        let valueData = Data("test-value".utf8)

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries["key1"] = valueData

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(
                casId: .any,
                entries: .any,
                fullHandle: .value("tuist/tuist"),
                serverURL: .value(URL(string: "https://example.com")!)
            )
            .willReturn()

        // When
        let response = try await subject.putValue(request: request, context: context)

        // Then
        #expect(response.hasError == false)

        verify(putCacheValueService)
            .putCacheValue(
                casId: .value("0~SDVUUkZaeVZXcEdZVTVzY0VaVVdHaHFZa2hDV2xsWWIzZFFVVDA5"),
                entries: .value(["key1": valueData.base64EncodedString()]),
                fullHandle: .any,
                serverURL: .any
            )
            .called(1)
    }

    @Test
    func putValue_when_service_throws_error() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let expectedError = PutCacheValueServiceError.forbidden("Access denied")

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(casId: .any, entries: .any, fullHandle: .any, serverURL: .any)
            .willThrow(expectedError)

        // When
        let response = try await subject.putValue(request: request, context: context)

        // Then
        #expect(response.hasError == true)
        #expect(response.error.description_p == "Access denied")
    }

    @Test
    func getValue_when_key_exists() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let valueData = "test-value"

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        let mockResponse = Operations.getCacheValue.Output.Ok.Body.jsonPayload(
            entries: [
                Operations.getCacheValue.Output.Ok.Body.jsonPayload.entriesPayloadPayload(
                    value: Data(valueData.utf8).base64EncodedString()
                ),
            ]
        )

        given(getCacheValueService)
            .getCacheValue(
                casId: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(mockResponse)

        // When
        let response = try await subject.getValue(request: request, context: context)

        // Then
        #expect(response.outcome == .success)

        switch response.contents {
        case let .value(value):
            #expect(value.entries["value"] == Data(valueData.utf8))
        default:
            #expect(Bool(false), "Expected .value content")
        }
    }

    @Test
    func getValue_when_key_not_found() async throws {
        // Given
        let key = Data("0test-key".utf8)

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        given(getCacheValueService)
            .getCacheValue(casId: .any, fullHandle: .any, serverURL: .any)
            .willReturn(nil)

        // When
        let response = try await subject.getValue(request: request, context: context)

        // Then
        #expect(response.outcome == .keyNotFound)
    }

    @Test
    func getValue_when_service_throws_error() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let expectedError = GetCacheValueServiceError.unauthorized("Invalid token")

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        given(getCacheValueService)
            .getCacheValue(casId: .any, fullHandle: .any, serverURL: .any)
            .willThrow(expectedError)

        // When
        let response = try await subject.getValue(request: request, context: context)

        // Then
        #expect(response.error.description_p == "Invalid token")
        #expect(response.outcome == .keyNotFound)
    }

    @Test
    func putValue_when_client_error_with_auth_error() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let authError = ServerClientAuthenticationError.notAuthenticated
        let clientError = ClientError(
            operationID: "putCacheValue",
            operationInput: "",
            causeDescription: "Authentication failed",
            underlyingError: authError
        )

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(casId: .any, entries: .any, fullHandle: .any, serverURL: .any)
            .willThrow(clientError)

        // When
        let response = try await subject.putValue(request: request, context: context)

        // Then
        #expect(response.hasError == true)
        #expect(response.error.description_p == "You must be logged in to do this.")
    }

    @Test
    func getValue_when_generic_error() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let genericError = NSError(domain: "TestDomain", code: 123, userInfo: nil)

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        given(getCacheValueService)
            .getCacheValue(casId: .any, fullHandle: .any, serverURL: .any)
            .willThrow(genericError)

        // When
        let response = try await subject.getValue(request: request, context: context)

        // Then
        #expect(response.error.description_p == genericError.localizedDescription)
        #expect(response.outcome == .keyNotFound)
    }

    @Test
    func putValue_when_successful_parses_and_stores_cas_mappings() async throws {
        // Given - Sample protobuf data containing CAS entries with node IDs and checksums
        let key = Data("test-key".utf8)
        let compilJobResultData = createSampleCompileJobResultData()

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries["value"] = compilJobResultData

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(casId: .any, entries: .any, fullHandle: .any, serverURL: .any)
            .willReturn()

        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willReturn()

        // When
        let response = try await subject.putValue(request: request, context: context)

        // Then
        #expect(response.hasError == false)

        // Verify that node mappings were stored - wait a bit for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify that CAS entries were found and stored (exact count based on sample data)
        verify(nodeStore)
            .storeNode(.any, checksum: .any)
            .called(4)
    }

    @Test
    func getValue_when_successful_parses_and_stores_cas_mappings() async throws {
        // Given
        let key = Data("test-key".utf8)
        let compilJobResultData = createSampleCompileJobResultData()

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        let mockResponse = Operations.getCacheValue.Output.Ok.Body.jsonPayload(
            entries: [
                Operations.getCacheValue.Output.Ok.Body.jsonPayload.entriesPayloadPayload(
                    value: compilJobResultData.base64EncodedString()
                ),
            ]
        )

        given(getCacheValueService)
            .getCacheValue(casId: .any, fullHandle: .any, serverURL: .any)
            .willReturn(mockResponse)

        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willReturn()

        // When
        let response = try await subject.getValue(request: request, context: context)

        // Then
        #expect(response.outcome == .success)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify that node mappings were stored during getValue
        verify(nodeStore)
            .storeNode(.any, checksum: .any)
            .called(4)
    }

    @Test
    func putValue_when_node_store_fails_continues_successfully() async throws {
        // Given
        let key = Data("test-key".utf8)
        let compilJobResultData = createSampleCompileJobResultData()

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries["value"] = compilJobResultData

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(casId: .any, entries: .any, fullHandle: .any, serverURL: .any)
            .willReturn()

        // Configure node store to fail
        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willThrow(NSError(domain: "TestError", code: 1))

        // When
        let response = try await subject.putValue(request: request, context: context)

        // Then - putValue should still succeed even if node store fails
        #expect(response.hasError == false)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify storeNode was attempted
        verify(nodeStore)
            .storeNode(.any, checksum: .any)
            .called(.atLeastOnce)
    }

    @Test
    func putValue_with_invalid_protobuf_data_handles_gracefully() async throws {
        // Given
        let key = Data("test-key".utf8)
        let invalidData = Data("invalid protobuf data".utf8)

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries["value"] = invalidData

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(casId: .any, entries: .any, fullHandle: .any, serverURL: .any)
            .willReturn()

        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willReturn()

        // When
        let response = try await subject.putValue(request: request, context: context)

        // Then - Should succeed even with invalid data (parseAndStoreMappings handles gracefully)
        #expect(response.hasError == false)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify no node mappings were stored for invalid data
        verify(nodeStore)
            .storeNode(.any, checksum: .any)
            .called(0)
    }

    @Test
    func putValue_with_partial_cas_entries_stores_valid_mappings() async throws {
        // Given
        let key = Data("test-key".utf8)
        let partialData = createPartialCASData()

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries["value"] = partialData

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(casId: .any, entries: .any, fullHandle: .any, serverURL: .any)
            .willReturn()

        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willReturn()

        // When
        let response = try await subject.putValue(request: request, context: context)

        // Then
        #expect(response.hasError == false)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        // Verify only one valid CAS entry was stored
        verify(nodeStore)
            .storeNode(.any, checksum: .any)
            .called(1)
    }

    // MARK: - Test Data Creation

    /// Creates sample protobuf data containing multiple CAS entries based on the provided base64 sample
    private func createSampleCompileJobResultData() -> Data {
        // This is the decoded sample data provided in the user request
        let base64String = "CggKBgUHGSIxMhKIARKFAQpBAM6T7x/ZgagCV1cJ/eoArXGgqkoemVtKGLwmEApO+lPFzsffgNISjh5WEXI2NfFf8PFhVtgbzBlf7epPht0pixISQEZDOUUzNUYxMzVFQjMyRUY2MzhDNkI2MkZGQjVDRjdGQTNCQUVDODU3MTI2MUY0OTM3MkIxQkJGMzhFQUQ1RkYSiAEShQEKQQDuCBKS2fNn5iPS1pHGQqOTOcPThh0HZDNuzrBBPxM1v8q9HyDn2Unr/kQeC/o7giYiOe5okCaEe6kaA0Iff2HfEkBBNTQwMkQ0QUYwRjM5QjRDOEI5RENCNTQ1OUQyNjA1M0JCNEJEODA1QkRGRjZBNDE4N0M5NTRGRDZEMkNDQTkzEogBEoUBCkEAsEe1Sil5IWaUNUsgFgtd2h9TsAf00ScoR77KBYuVPF6Z3U8TEYB8UjCPsvQbJVSkqoDGCjiw5JwX5M03cURp3xJANzQ0MEE1QkVCREYzRUM0OTMzNDQyMzU4RkM3OEM0NTc3NjBBRDlEODg0NTVGNjZFN0JEMDM2N0QyOTNFOUM0NhIECgJbXRICCgASiAEShQEKQQDYpyEt5l9N6vDZJWAkbzRx6oc7Fzzk79gPQkaKnppnLyxWS9GYUIFptcnzKJwc9Io3v1qg/vB45Xq21Ra8O1PyEkBBQjJENjQ4QkZGNTUxMjQxQzk4QkYyNzlFN0E1M0I2RDJENDFGQUY0MjFBMzNDMjUzNkIwMERFNTE1NzJFRkNBEiwKKnN3aWZ0OjpjYXM6OnNjaGVtYTo6Y29tcGlsZV9qb2JfcmVzdWx0Ojp2MQ=="
        return Data(base64Encoded: base64String)!
    }

    /// Creates test data with only one valid CAS entry
    private func createPartialCASData() -> Data {
        var data = Data()

        // Add some metadata first
        data.append(contentsOf: [0x0A, 0x08, 0x0A, 0x06, 0x05, 0x07, 0x19, 0x22, 0x31, 0x32])

        // Add one complete CAS entry: 0x0A 0x41 0x00 + 64 bytes CAS ID + 0x12 0x40 + 64 bytes hex
        data.append(contentsOf: [0x12, 0x88, 0x01, 0x12, 0x85, 0x01])
        data.append(contentsOf: [0x0A, 0x41, 0x00]) // CAS entry marker

        // 64 bytes of CAS ID
        let casID = Data(repeating: 0xAB, count: 64)
        data.append(casID)

        // 0x12 0x40 marker for hex data
        data.append(contentsOf: [0x12, 0x40])

        // 64 bytes of hex checksum (valid hex characters)
        let hexString = "ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890"
        data.append(hexString.data(using: .ascii)!)

        return data
    }
}

extension ServerContext {
    fileprivate static func test() -> ServerContext {
        let serviceDescriptor = ServiceDescriptor(fullyQualifiedService: "CompilationCacheService.Keyvalue.V1.KeyValueDB")
        let methodDescriptor = MethodDescriptor(service: serviceDescriptor, method: "test")
        let cancellationHandle = ServerContext.RPCCancellationHandle()

        return ServerContext(
            descriptor: methodDescriptor,
            remotePeer: "test:client",
            localPeer: "test:server",
            cancellation: cancellationHandle
        )
    }
}
