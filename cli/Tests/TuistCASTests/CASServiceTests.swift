import CryptoKit
import FileSystem
import Foundation
import GRPCCore
import Mockable
import OpenAPIRuntime
import Path
import Testing
import TuistCache
import TuistCASAnalytics
import TuistHTTP
import TuistServer
import TuistSupport
@testable import TuistCAS

struct CASServiceTests {
    private let subject: CASService
    private let cacheURLStore: MockCacheURLStoring
    private let saveCacheCASService: MockSaveCacheCASServicing
    private let loadCacheCASService: MockLoadCacheCASServicing
    private let dataCompressingService: MockDataCompressingServicing
    private let metadataStore: MockCASOutputMetadataStoring
    private let serverAuthenticationController: MockServerAuthenticationControlling
    private let fullHandle = "account-handle/project-handle"
    private let serverURL = URL(string: "https://example.com")!
    private let cacheURL = URL(string: "https://cache.example.com")!

    init() {
        cacheURLStore = .init()
        saveCacheCASService = .init()
        loadCacheCASService = .init()
        dataCompressingService = .init()
        metadataStore = .init()
        serverAuthenticationController = .init()

        given(cacheURLStore)
            .getCacheURL(for: .any, accountHandle: .any)
            .willReturn(URL(string: "https://cache.example.com")!)

        given(serverAuthenticationController)
            .authenticationToken(serverURL: .any)
            .willReturn(AuthenticationToken.project("mock-token"))

        subject = CASService(
            fullHandle: fullHandle,
            serverURL: serverURL,
            cacheURLStore: cacheURLStore,
            saveCacheCASService: saveCacheCASService,
            loadCacheCASService: loadCacheCASService,
            fileSystem: FileSystem(),
            dataCompressingService: dataCompressingService,
            metadataStore: metadataStore,
            serverAuthenticationController: serverAuthenticationController
        )
    }

    @Test
    func load_when_successful() async throws {
        // Given
        let casID = "test-cas-id"
        let compressedData = Data("compressed-data".utf8)
        let expectedData = Data("test-data".utf8)

        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID.id = casID.data(using: .utf8)!

        let context = ServerContext.test()

        given(loadCacheCASService)
            .loadCacheCAS(
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willReturn(compressedData)

        given(dataCompressingService)
            .decompress(.any)
            .willReturn(expectedData)

        given(metadataStore)
            .storeMetadata(.any, for: .any)
            .willReturn()

        // When
        let response = try await subject.load(request: request, context: context)

        // Then
        #expect(response.outcome == .success)

        switch response.contents {
        case let .data(blob):
            #expect(blob.blob.data == expectedData)
        default:
            #expect(Bool(false), "Expected .data content")
        }

        verify(loadCacheCASService)
            .loadCacheCAS(
                casId: .value(casID),
                fullHandle: .value(fullHandle),
                serverURL: .any,
                authenticationURL: .value(serverURL),
                serverAuthenticationController: .any
            )
            .called(1)

        verify(dataCompressingService)
            .decompress(.value(compressedData))
            .called(1)

        try await Task.sleep(for: .milliseconds(100))

        verify(metadataStore)
            .storeMetadata(.any, for: .value(casID))
            .called(1)
    }

    @Test
    func load_when_service_throws_error() async throws {
        // Given
        let casID = "test-cas-id"
        let expectedError = LoadCacheCASServiceError.unknownError(404)

        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID.id = casID.data(using: .utf8)!

        let context = ServerContext.test()

        given(loadCacheCASService)
            .loadCacheCAS(
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(expectedError)

        // When
        let response = try await subject.load(request: request, context: context)

        // Then
        #expect(response.outcome == .error)
        #expect(response.error.description_p.contains("404"))

        switch response.contents {
        case let .error(error):
            #expect(error.description_p.contains("404"))
        default:
            #expect(Bool(false), "Expected .error content")
        }
    }

    @Test
    func save_with_direct_data() async throws {
        // Given
        let testData = Data("direct test data".utf8)
        let compressedData = Data("compressed-data".utf8)

        var request = CompilationCacheService_Cas_V1_CASSaveRequest()
        request.data.blob.data = testData

        let context = ServerContext.test()

        given(dataCompressingService)
            .compress(.any)
            .willReturn(compressedData)

        given(saveCacheCASService)
            .saveCacheCAS(
                .any,
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willReturn()

        given(metadataStore)
            .storeMetadata(.any, for: .any)
            .willReturn()

        // When
        let response = try await subject.save(request: request, context: context)

        // Then
        let fingerprint = "74E40A3FAE0D089D887556DBE3001075455BB28A7EAD99D6DE81A85EF3F3E4A8"
        #expect(response.casID.id == fingerprint.data(using: .utf8)!)
        switch response.contents {
        case .casID:
            break
        case .error:
            #expect(Bool(false), "Expected success, but got error")
        case .none:
            #expect(Bool(false), "Expected success, but contents is nil")
        }

        verify(dataCompressingService)
            .compress(.value(testData))
            .called(1)

        verify(saveCacheCASService)
            .saveCacheCAS(
                .value(compressedData),
                casId: .value(fingerprint),
                fullHandle: .value(fullHandle),
                serverURL: .any,
                authenticationURL: .value(serverURL),
                serverAuthenticationController: .any
            )
            .called(1)

        try await Task.sleep(for: .milliseconds(100))

        verify(metadataStore)
            .storeMetadata(.any, for: .value(fingerprint))
            .called(1)
    }

    @Test
    func save_when_upload_fails() async throws {
        // Given
        let testData = Data("test data".utf8)
        let compressedData = Data("compressed-data".utf8)
        let expectedError = SaveCacheCASServiceError.forbidden("Upload denied")

        var request = CompilationCacheService_Cas_V1_CASSaveRequest()
        request.data.blob.data = testData

        let context = ServerContext.test()

        given(dataCompressingService)
            .compress(.any)
            .willReturn(compressedData)

        given(saveCacheCASService)
            .saveCacheCAS(
                .any,
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(expectedError)

        // When
        let response = try await subject.save(request: request, context: context)

        // Then
        switch response.contents {
        case let .error(error):
            #expect(error.description_p == "Upload denied")
        case .casID:
            #expect(Bool(false), "Expected error, but got casID")
        case .none:
            #expect(Bool(false), "Expected error, but contents is nil")
        }
    }

    @Test
    func load_when_client_error_with_auth_error() async throws {
        // Given
        let casID = "test-cas-id"
        let authError = ClientAuthenticationError.notAuthenticated
        let clientError = ClientError(
            operationID: "loadCacheCAS",
            operationInput: "",
            causeDescription: "Authentication failed",
            underlyingError: authError
        )

        var request = CompilationCacheService_Cas_V1_CASLoadRequest()
        request.casID.id = casID.data(using: .utf8)!

        let context = ServerContext.test()

        given(loadCacheCASService)
            .loadCacheCAS(
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(clientError)

        // When
        let response = try await subject.load(request: request, context: context)

        // Then
        #expect(response.outcome == .error)
        #expect(response.error.description_p == "You must be logged in to do this.")
    }

    @Test
    func save_when_generic_error() async throws {
        // Given
        let testData = Data("test data".utf8)
        let compressedData = Data("compressed-data".utf8)
        let genericError = NSError(domain: "TestDomain", code: 500, userInfo: nil)

        var request = CompilationCacheService_Cas_V1_CASSaveRequest()
        request.data.blob.data = testData

        let context = ServerContext.test()

        given(dataCompressingService)
            .compress(.any)
            .willReturn(compressedData)

        given(saveCacheCASService)
            .saveCacheCAS(
                .any,
                casId: .any,
                fullHandle: .any,
                serverURL: .any,
                authenticationURL: .any,
                serverAuthenticationController: .any
            )
            .willThrow(genericError)

        // When
        let response = try await subject.save(request: request, context: context)

        // Then
        switch response.contents {
        case let .error(error):
            #expect(error.description_p == genericError.localizedDescription)
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
