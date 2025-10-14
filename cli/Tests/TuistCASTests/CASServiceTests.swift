import CryptoKit
import Foundation
import GRPCCore
import Mockable
import Path
import Testing
import TuistServer
import TuistSupport
@testable import TuistCAS

struct CASServiceTests {
    private var subject: CASService!
    private var uploadCASArtifactService: MockUploadCASArtifactServicing!
    private var loadCASService: MockLoadCASServicing!
    private let fullHandle = "account-handle/project-handle"
    private let serverURL = URL(string: "https://example.com")!
    
    init() {
        uploadCASArtifactService = .init()
        loadCASService = .init()
        
        subject = CASService(
            fullHandle: fullHandle,
            serverURL: serverURL,
            uploadCASArtifactService: uploadCASArtifactService,
            loadCASService: loadCASService
        )
    }
    
    @Test
    func test_load_when_successful() async throws {
        // Given
        let casID = "test-cas-id"
        let expectedData = Data("test-data".utf8)
        
        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID.id = casID.data(using: .utf8)!
        
        let context = ServerContext.test()
        
        given(loadCASService)
            .loadCAS(
                casId: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn(expectedData)
        
        // When
        let response = try await subject.load(request: request, context: context)
        
        // Then
        #expect(response.outcome == .success)
        
        switch response.contents {
        case .data(let blob):
            #expect(blob.blob.data == expectedData)
        default:
            #expect(Bool(false), "Expected .data content")
        }
        
        verify(loadCASService)
            .loadCAS(
                casId: .value(casID),
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL)
            )
            .called(1)
    }
    
    @Test
    func test_load_when_service_throws_error() async throws {
        // Given
        let casID = "test-cas-id"
        let expectedError = LoadCASServiceError.unknownError(404)
        
        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID.id = casID.data(using: .utf8)!
        
        let context = ServerContext.test()
        
        given(loadCASService)
            .loadCAS(casId: .any, fullHandle: .any, serverURL: .any)
            .willThrow(expectedError)
        
        // When
        let response = try await subject.load(request: request, context: context)
        
        // Then
        #expect(response.outcome == .error)
        #expect(response.error.description_p.contains("404"))
        
        switch response.contents {
        case .error(let error):
            #expect(error.description_p.contains("404"))
        default:
            #expect(Bool(false), "Expected .error content")
        }
    }
    
    @Test
    func test_save_with_direct_data() async throws {
        // Given
        let testData = Data("direct test data".utf8)
        
        var request = CompilationCacheService_Cas_V1_CASSaveRequest()
        request.data.blob.data = testData
        
        let context = ServerContext.test()
        
        given(uploadCASArtifactService)
            .uploadCASArtifact(
                .any,
                casId: .any,
                fullHandle: .any,
                serverURL: .any
            )
            .willReturn()
        
        // When
        let response = try await subject.save(request: request, context: context)
        
        // Then
        let expectedDigest = SHA512.hash(data: testData).description
        let expectedCASIDData = expectedDigest.data(using: .utf8)!
        
        #expect(response.casID.id == expectedCASIDData)
        switch response.contents {
        case .casID:
            break
        case .error:
            #expect(Bool(false), "Expected success, but got error")
        case .none:
            #expect(Bool(false), "Expected success, but contents is nil")
        }
        
        verify(uploadCASArtifactService)
            .uploadCASArtifact(
                .value(testData),
                casId: .value(expectedDigest),
                fullHandle: .value(fullHandle),
                serverURL: .value(serverURL)
            )
            .called(1)
    }
    
    
    @Test
    func test_save_when_upload_fails() async throws {
        // Given
        let testData = Data("test data".utf8)
        let expectedError = UploadCASArtifactServiceError.forbidden("Upload denied")
        
        var request = CompilationCacheService_Cas_V1_CASSaveRequest()
        request.data.blob.data = testData
        
        let context = ServerContext.test()
        
        given(uploadCASArtifactService)
            .uploadCASArtifact(.any, casId: .any, fullHandle: .any, serverURL: .any)
            .willThrow(expectedError)
        
        // When
        let response = try await subject.save(request: request, context: context)
        
        // Then
        switch response.contents {
        case .error(let error):
            #expect(error.description_p == "Upload denied")
        case .casID:
            #expect(Bool(false), "Expected error, but got casID")
        case .none:
            #expect(Bool(false), "Expected error, but contents is nil")
        }
    }
}

extension ServerContext {
    fileprivate static func test() -> ServerContext {
        let serviceDescriptor = ServiceDescriptor(fullyQualifiedService: "CompilationCacheService.Cas.V1.CASDBService")
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
