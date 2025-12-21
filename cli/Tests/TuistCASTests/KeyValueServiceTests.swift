import Foundation
import GRPCCore
import Mockable
import OpenAPIRuntime
import Testing
import TuistCache
import TuistHTTP
import TuistServer
import TuistSupport
import TuistTesting
@testable import TuistCAS
@testable import TuistCASAnalytics

struct KeyValueServiceTests {
    private let subject: KeyValueService
    private let cacheURLStore: MockCacheURLStoring
    private let putCacheValueService: MockPutCacheValueServicing
    private let getCacheValueService: MockGetCacheValueServicing
    private let nodeStore: MockCASNodeStoring
    private let metadataStore: MockKeyValueMetadataStoring
    private let serverAuthenticationController: MockServerAuthenticationControlling
    private let fullHandle = "tuist/tuist"
    private let serverURL = URL(string: "https://example.com")!
    private let cacheURL = URL(string: "https://cache.example.com")!
    /// Sample protobuf data containing multiple CAS entries
    private let compileJobResultEntry = Data(
        base64Encoded: "CggKBgUHGSIxMhKIARKFAQpBAM6T7x/ZgagCV1cJ/eoArXGgqkoemVtKGLwmEApO+lPFzsffgNISjh5WEXI2NfFf8PFhVtgbzBlf7epPht0pixISQEZDOUUzNUYxMzVFQjMyRUY2MzhDNkI2MkZGQjVDRjdGQTNCQUVDODU3MTI2MUY0OTM3MkIxQkJGMzhFQUQ1RkYSiAEShQEKQQDuCBKS2fNn5iPS1pHGQqOTOcPThh0HZDNuzrBBPxM1v8q9HyDn2Unr/kQeC/o7giYiOe5okCaEe6kaA0Iff2HfEkBBNTQwMkQ0QUYwRjM5QjRDOEI5RENCNTQ1OUQyNjA1M0JCNEJEODA1QkRGRjZBNDE4N0M5NTRGRDZEMkNDQTkzEogBEoUBCkEAsEe1Sil5IWaUNUsgFgtd2h9TsAf00ScoR77KBYuVPF6Z3U8TEYB8UjCPsvQbJVSkqoDGCjiw5JwX5M03cURp3xJANzQ0MEE1QkVCREYzRUM0OTMzNDQyMzU4RkM3OEM0NTc3NjBBRDlEODg0NTVGNjZFN0JEMDM2N0QyOTNFOUM0NhIECgJbXRICCgASiAEShQEKQQDYpyEt5l9N6vDZJWAkbzRx6oc7Fzzk79gPQkaKnppnLyxWS9GYUIFptcnzKJwc9Io3v1qg/vB45Xq21Ra8O1PyEkBBQjJENjQ4QkZGNTUxMjQxQzk4QkYyNzlFN0E1M0I2RDJENDFGQUY0MjFBMzNDMjUzNkIwMERFNTE1NzJFRkNBEiwKKnN3aWZ0OjpjYXM6OnNjaGVtYTo6Y29tcGlsZV9qb2JfcmVzdWx0Ojp2MQ=="
    )!

    init() {
        cacheURLStore = MockCacheURLStoring()
        putCacheValueService = MockPutCacheValueServicing()
        getCacheValueService = MockGetCacheValueServicing()
        nodeStore = MockCASNodeStoring()
        metadataStore = MockKeyValueMetadataStoring()
        serverAuthenticationController = MockServerAuthenticationControlling()

        given(cacheURLStore)
            .getCacheURL(for: .any, accountHandle: .any)
            .willReturn(URL(string: "https://cache.example.com")!)

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(AuthenticationToken.project("mock-token"))

        subject = KeyValueService(
            fullHandle: fullHandle,
            serverURL: serverURL,
            cacheURLStore: cacheURLStore,
            putCacheValueService: putCacheValueService,
            getCacheValueService: getCacheValueService,
            nodeStore: nodeStore,
            metadataStore: metadataStore,
            serverAuthenticationController: serverAuthenticationController
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
                serverURL: .any,
                authenticationURL: .value(URL(string: "https://example.com")!),
                serverAuthenticationController: .any
            )
            .willReturn()

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
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
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .called(1)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        verify(metadataStore)
            .storeMetadata(
                .any,
                for: .value("0~SDVUUkZaeVZXcEdZVTVzY0VaVVdHaHFZa2hDV2xsWWIzZFFVVDA5"),
                operationType: .value(.write)
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
            .putCacheValue(
                casId: .any,
                entries: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
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

        let mockResponse = KeyValueResponse(
            entries: [
                KeyValueEntry(value: Data(valueData.utf8).base64EncodedString()),
            ]
        )

        given(getCacheValueService)
            .getCacheValue(
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willReturn(mockResponse)

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
            .willReturn()

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

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        verify(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .value(.read))
            .called(1)
    }

    @Test
    func getValue_when_key_not_found() async throws {
        // Given
        let key = Data("0test-key".utf8)

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        given(getCacheValueService)
            .getCacheValue(
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willReturn(nil)

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
            .willReturn()

        // When
        let response = try await subject.getValue(request: request, context: context)

        // Then
        #expect(response.outcome == .keyNotFound)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        verify(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .value(.read))
            .called(1)
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
            .getCacheValue(
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(expectedError)

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
            .willReturn()

        // When
        let response = try await subject.getValue(request: request, context: context)

        // Then
        #expect(response.error.description_p == "Invalid token")
        #expect(response.outcome == .keyNotFound)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        verify(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .value(.read))
            .called(1)
    }

    @Test
    func putValue_when_client_error_with_auth_error() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let authError = ClientAuthenticationError.notAuthenticated
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
            .putCacheValue(
                casId: .any,
                entries: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
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
            .getCacheValue(
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(genericError)

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
            .willReturn()

        // When
        let response = try await subject.getValue(request: request, context: context)

        // Then
        #expect(response.error.description_p == genericError.localizedDescription)
        #expect(response.outcome == .keyNotFound)

        // Wait for async Task to complete
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds

        verify(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .value(.read))
            .called(1)
    }

    @Test
    func putValue_when_successful_parses_and_stores_cas_mappings() async throws {
        // Given
        let key = Data("test-key".utf8)

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries["value"] = compileJobResultEntry

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(
                casId: .any,
                entries: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willReturn()

        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willReturn()

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
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

        verify(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .value(.write))
            .called(1)
    }

    @Test
    func getValue_when_successful_parses_and_stores_cas_mappings() async throws {
        // Given
        let key = Data("test-key".utf8)

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        let mockResponse = KeyValueResponse(
            entries: [
                KeyValueEntry(value: compileJobResultEntry.base64EncodedString()),
            ]
        )

        given(getCacheValueService)
            .getCacheValue(
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willReturn(mockResponse)

        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willReturn()

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
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

        verify(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .value(.read))
            .called(1)
    }

    @Test
    func putValue_when_node_store_fails_continues_successfully() async throws {
        // Given
        let key = Data("test-key".utf8)

        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries["value"] = compileJobResultEntry

        let context = ServerContext.test()

        given(putCacheValueService)
            .putCacheValue(
                casId: .any,
                entries: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willReturn()

        // Configure node store to fail
        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willThrow(NSError(domain: "TestError", code: 1))

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
            .willReturn()

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

        verify(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .value(.write))
            .called(1)
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
            .putCacheValue(
                casId: .any,
                entries: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willReturn()

        given(nodeStore)
            .storeNode(.any, checksum: .any)
            .willReturn()

        given(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .any)
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

        verify(metadataStore)
            .storeMetadata(.any, for: .any, operationType: .value(.write))
            .called(1)
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
