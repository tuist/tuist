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

@available(macOS 15.0, *)
public struct CASDBServiceImpl: CompilationCacheService_Cas_V1_CASDBService.SimpleServiceProtocol {
    private let config: TuistCore.Tuist
    private let uploadCASArtifactService: UploadCASArtifactServicing
    private let loadCASService: LoadCASServicing
    
    public init(config: TuistCore.Tuist, uploadCASArtifactService: UploadCASArtifactServicing = UploadCASArtifactService(), loadCASService: LoadCASServicing = LoadCASService()) {
        self.config = config
        self.uploadCASArtifactService = uploadCASArtifactService
        self.loadCASService = loadCASService
    }

    public func load(request: CompilationCacheService_Cas_V1_CASLoadRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASLoadResponse {
        let casID = String(data: request.casID.id, encoding: .utf8)!
        
        let serverURL = config.url
        let fullHandle = config.fullHandle!
        
        var response = CompilationCacheService_Cas_V1_CASLoadResponse()
        
        do {
            let data = try await loadCASService.loadCAS(
                casId: casID.hasPrefix("0~") ? String(casID.dropFirst(2)) : casID,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            
            var bytes = CompilationCacheService_Cas_V1_CASBytes()
            bytes.data = data

            // Create response with the loaded data
            var blob = CompilationCacheService_Cas_V1_CASBlob()
            blob.blob = bytes
            
            response.contents = .data(blob)
            response.outcome = .success
        } catch let error {
            response.outcome = .error
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = error.localizedDescription
            response.contents = .error(responseError)
        }
        
        return response
    }
    
    public func put(request: CompilationCacheService_Cas_V1_CASPutRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASPutResponse {
        fatalError()
    }
    
    public func get(request: CompilationCacheService_Cas_V1_CASGetRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASGetResponse {
        fatalError()
    }
    
    public func save(
        request: CompilationCacheService_Cas_V1_CASSaveRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASSaveResponse {
        let serverURL = config.url
        
        guard let fullHandle = config.fullHandle else { fatalError() }
        
        // Compute SHA-512 checksum of the data
        let data: Data
        if !request.data.blob.filePath.isEmpty {
            // Read data from file path
            let fileURL = URL(fileURLWithPath: request.data.blob.filePath)
            data = try Data(contentsOf: fileURL)
        } else {
            // Use the provided data
            data = request.data.blob.data
        }
        
        let digest = SHA512.hash(data: data)
        let hashData = Data(digest)
        let casID = hashData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        
        try! await uploadCASArtifactService.uploadCASArtifact(
            data,
            casId: casID,
            fullHandle: fullHandle,
            serverURL: serverURL
        )
        
        var response = CompilationCacheService_Cas_V1_CASSaveResponse()
        var message = CompilationCacheService_Cas_V1_CASDataID()
        message.id = ("0~" + casID).data(using: String.Encoding.utf8)!
        response.casID = message
        return response
    }
}
