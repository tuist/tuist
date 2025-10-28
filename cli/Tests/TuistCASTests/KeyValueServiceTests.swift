import Foundation
import GRPCCore
import Mockable
import OpenAPIRuntime
import Path
import Testing
import TuistServer
import TuistSupport
import FileSystem
import FileSystemTesting
import TuistTesting
@testable import TuistCAS

struct KeyValueServiceTests {
    private let subject: KeyValueService
    private let putCacheValueService: MockPutCacheValueServicing
    private let getCacheValueService: MockGetCacheValueServicing
    private let fullHandle = "tuist/tuist"
    private let serverURL = URL(string: "https://example.com")!

    init() {
        putCacheValueService = .init()
        getCacheValueService = .init()

        subject = KeyValueService(
            fullHandle: fullHandle,
            serverURL: serverURL,
            putCacheValueService: putCacheValueService,
            getCacheValueService: getCacheValueService
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

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func getValue_saves_keyvalue_entries_to_file() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.cacheDirectory = temporaryDirectory
        let fileSystem = FileSystem()
        
        let key = Data("0test-key".utf8)
        let entryKey1 = Data("test-data1".utf8).base64EncodedString()
        let entryKey2 = Data("test-data2".utf8).base64EncodedString()
        
        let subject = KeyValueService(
            fullHandle: fullHandle,
            serverURL: serverURL,
            putCacheValueService: putCacheValueService,
            getCacheValueService: getCacheValueService,
            fileSystem: fileSystem,
            environment: environment
        )

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        let mockResponse = Operations.getCacheValue.Output.Ok.Body.jsonPayload(
            entries: [
                Operations.getCacheValue.Output.Ok.Body.jsonPayload.entriesPayloadPayload(
                    value: entryKey1
                ),
                Operations.getCacheValue.Output.Ok.Body.jsonPayload.entriesPayloadPayload(
                    value: entryKey2
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
        
        // Verify the response contains expected values
        switch response.contents {
        case let .value(value):
            // The implementation overwrites the "value" key in each iteration, so only the last entry's data will be present
            #expect(value.entries["value"] == Data("test-data2".utf8))
        default:
            #expect(Bool(false), "Expected .value content")
        }
        
        // Wait a bit for the async file save to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let keyValueEntriesDirectory = temporaryDirectory.appending(component: "keyvalue-entries")
        let expectedFilePath = keyValueEntriesDirectory.appending(component: "0~dGVzdC1rZXk=.json")
        
        #expect(try await fileSystem.exists(expectedFilePath))
        
        let fileData = try Data(contentsOf: expectedFilePath.url)
        let savedEntryKeys = try JSONDecoder().decode([String].self, from: fileData)
        
        #expect(savedEntryKeys == [entryKey1, entryKey2])
    }

    @Test(.inTemporaryDirectory, .withMockedEnvironment())
    func getValue_handles_empty_entries() async throws {
        // Given
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let environment = try #require(Environment.mocked)
        environment.cacheDirectory = temporaryDirectory
        let fileSystem = FileSystem()
        
        let key = Data("0test-key".utf8)
        
        let subject = KeyValueService(
            fullHandle: fullHandle,
            serverURL: serverURL,
            putCacheValueService: putCacheValueService,
            getCacheValueService: getCacheValueService,
            fileSystem: fileSystem,
            environment: environment
        )

        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key

        let context = ServerContext.test()

        // Empty entries
        let mockResponse = Operations.getCacheValue.Output.Ok.Body.jsonPayload(
            entries: []
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
        
        // Wait a bit for the async file save to complete
        try await Task.sleep(nanoseconds: 200_000_000) // 200ms
        
        let keyValueEntriesDirectory = temporaryDirectory.appending(component: "keyvalue-entries")
        let expectedFilePath = keyValueEntriesDirectory.appending(component: "0~dGVzdC1rZXk=.json")
        
        #expect(try await fileSystem.exists(expectedFilePath))
        
        let fileData = try Data(contentsOf: expectedFilePath.url)
        let savedEntryKeys = try JSONDecoder().decode([String].self, from: fileData)
        
        #expect(savedEntryKeys.isEmpty)
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
