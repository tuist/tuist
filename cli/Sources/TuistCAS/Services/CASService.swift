import CommonCrypto
import CryptoKit
@preconcurrency import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import Path
import SwiftProtobuf
import TuistCore
import TuistServer

public enum CASServiceError: LocalizedError {
    case invalidCASID
    case methodNotImplemented(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidCASID:
            return "Invalid CAS ID: Unable to decode CAS ID as UTF-8 string"
        case .methodNotImplemented(let method):
            return "Method '\(method)' is not implemented"
        }
    }
}

public struct CASService: CompilationCacheService_Cas_V1_CASDBService.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let uploadCASArtifactService: UploadCASArtifactServicing
    private let loadCASService: LoadCASServicing
    private let fileSystem: FileSysteming
    
    public init(
        fullHandle: String,
        serverURL: URL,
        uploadCASArtifactService: UploadCASArtifactServicing = UploadCASArtifactService(),
        loadCASService: LoadCASServicing = LoadCASService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fullHandle = fullHandle
        self.serverURL  = serverURL
        self.uploadCASArtifactService = uploadCASArtifactService
        self.loadCASService = loadCASService
        self.fileSystem = fileSystem
    }

    public func load(request: CompilationCacheService_Cas_V1_CASLoadRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASLoadResponse {
        guard let casID = String(data: request.casID.id, encoding: .utf8) else {
            throw CASServiceError.invalidCASID
        }
        
        var response = CompilationCacheService_Cas_V1_CASLoadResponse()
        
        do {
            let data = try await loadCASService.loadCAS(
                casId: casID,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            
            var bytes = CompilationCacheService_Cas_V1_CASBytes()
            bytes.data = data
            
            var blob = CompilationCacheService_Cas_V1_CASBlob()
            blob.blob = bytes
            
            response.contents = .data(blob)
            response.outcome = .success
        } catch let error {
            response.outcome = .error
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            response.error = responseError
            response.contents = .error(responseError)
        }
        
        return response
    }

    public func save(
        request: CompilationCacheService_Cas_V1_CASSaveRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASSaveResponse {
        let data: Data
        if !request.data.blob.filePath.isEmpty {
            data = try await fileSystem.readFile(
                at: try AbsolutePath(validating: request.data.blob.filePath)
            )
        } else {
            data = request.data.blob.data
        }
        
        let digest = SHA512.hash(data: data)
        
        var response = CompilationCacheService_Cas_V1_CASSaveResponse()
        
        var message = CompilationCacheService_Cas_V1_CASDataID()
        message.id = digest.description.data(using: .utf8)!
        
        do {
            try await uploadCASArtifactService.uploadCASArtifact(
                data,
                casId: digest.description,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            response.casID = message
            response.contents = .casID(message)
        } catch let error {
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            response.error = responseError
            response.contents = .error(responseError)
        }
        
        return response
    }
    
    public func put(request: CompilationCacheService_Cas_V1_CASPutRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASPutResponse {
        throw CASServiceError.methodNotImplemented("put")
    }
    
    public func get(request: CompilationCacheService_Cas_V1_CASGetRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASGetResponse {
        throw CASServiceError.methodNotImplemented("get")
    }
}
