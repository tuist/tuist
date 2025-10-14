import Foundation
import GRPCCore
import Mockable
import Path
import Testing
import TuistServer
import TuistSupport
@testable import TuistCAS

struct KeyValueServiceTests {
    private var subject: KeyValueService!
    private var putKeyValueService: MockPutKeyValueServicing!
    private var getKeyValueService: MockGetKeyValueServicing!
    private let fullHandle = "tuist/tuist"
    private let serverURL = URL(string: "https://example.com")!
    
    init() {
        putKeyValueService = .init()
        getKeyValueService = .init()
        
        subject = KeyValueService(
            fullHandle: fullHandle,
            serverURL: serverURL,
            putKeyValueService: putKeyValueService,
            getKeyValueService: getKeyValueService
        )
    }
    
    @Test
    func test_putValue_when_successful() async throws {
        // Given
        let key = Data("MH5TRFZyVWpGYU5scEZUWGhqYkhCWllYb3dQUT09".utf8)
        let valueData = Data("test-value".utf8)
        
        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        request.value.entries["key1"] = valueData
        
        let context = ServerContext.test()
        
        given(putKeyValueService)
            .putKeyValue(
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
        
        verify(putKeyValueService)
            .putKeyValue(
                casId: .value("0~SDVUUkZaeVZXcEdZVTVzY0VaVVdHaHFZa2hDV2xsWWIzZFFVVDA5"),
                entries: .value(["key1": valueData.base64EncodedString()]),
                fullHandle: .any,
                serverURL: .any
            )
            .called(1)
    }
    
    
    @Test
    func test_putValue_when_service_throws_error() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let expectedError = PutKeyValueServiceError.forbidden("Access denied")
        
        var request = CompilationCacheService_Keyvalue_V1_PutValueRequest()
        request.key = key
        
        let context = ServerContext.test()
        
        given(putKeyValueService)
            .putKeyValue(casId: .any, entries: .any, fullHandle: .any, serverURL: .any)
            .willThrow(expectedError)
        
        // When
        let response = try await subject.putValue(request: request, context: context)
        
        // Then
        #expect(response.hasError == true)
        #expect(response.error.description_p == "Access denied")
    }
    
    @Test
    func test_getValue_when_key_exists() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let valueData = "test-value"
        
        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key
        
        let context = ServerContext.test()
        
        let mockResponse = Operations.getKeyValue.Output.Ok.Body.jsonPayload(
            entries: [
                Operations.getKeyValue.Output.Ok.Body.jsonPayload.entriesPayloadPayload(
                    value: Data(valueData.utf8).base64EncodedString()
                )
            ]
        )
        
        given(getKeyValueService)
            .getKeyValue(
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
    func test_getValue_when_key_not_found() async throws {
        // Given
        let key = Data("0test-key".utf8)
        
        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key
        
        let context = ServerContext.test()
        
        given(getKeyValueService)
            .getKeyValue(casId: .any, fullHandle: .any, serverURL: .any)
            .willReturn(nil)
        
        // When
        let response = try await subject.getValue(request: request, context: context)
        
        // Then
        #expect(response.outcome == .keyNotFound)
    }
    
    
    @Test
    func test_getValue_when_service_throws_error() async throws {
        // Given
        let key = Data("0test-key".utf8)
        let expectedError = GetKeyValueServiceError.unauthorized("Invalid token")
        
        var request = CompilationCacheService_Keyvalue_V1_GetValueRequest()
        request.key = key
        
        let context = ServerContext.test()
        
        given(getKeyValueService)
            .getKeyValue(casId: .any, fullHandle: .any, serverURL: .any)
            .willThrow(expectedError)
        
        // When
        let response = try await subject.getValue(request: request, context: context)
        
        // Then
        #expect(response.error.description_p == "Invalid token")
        #expect(response.outcome == .keyNotFound)
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
