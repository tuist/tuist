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
public struct KeyValueService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol {
    private let config: TuistCore.Tuist
    private let putKeyValueService: PutKeyValueServicing
    private let getKeyValueService: GetKeyValueServicing
    
    public init(config: TuistCore.Tuist, putKeyValueService: PutKeyValueServicing = PutKeyValueService(), getKeyValueService: GetKeyValueServicing = GetKeyValueService()) {
        self.config = config
        self.putKeyValueService = putKeyValueService
        self.getKeyValueService = getKeyValueService
    }
    
    public func putValue(request: CompilationCacheService_Keyvalue_V1_PutValueRequest, context: ServerContext) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        let binaryKey = request.key.dropFirst()
        let casID = "0~" + binaryKey.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        
        let serverURL = config.url
        guard let fullHandle = config.fullHandle else {
            return CompilationCacheService_Keyvalue_V1_PutValueResponse()
        }
        
        // Convert protobuf entries to [String: String] format
        var entries: [String: String] = [:]
        for (key, data) in request.value.entries {
            entries[key] = data.base64EncodedString()
        }
        
        var response = CompilationCacheService_Keyvalue_V1_PutValueResponse()
        do {
            try await putKeyValueService.putKeyValue(
                casId: casID,
                entries: entries,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            return response
        } catch let error {
            var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
            responseError.description_p = error.localizedDescription
            response.error = responseError
            return response
        }
    }
    
    public func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        let casID = "0~" + request.key.dropFirst().base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        
        let serverURL = config.url
        guard let fullHandle = config.fullHandle else {
            var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
            response.outcome = .keyNotFound
            return response
        }
        
        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
        
        do {
            if let json = try await getKeyValueService.getKeyValue(
                casId: casID,
                fullHandle: fullHandle,
                serverURL: serverURL
            ) {
                var value = CompilationCacheService_Keyvalue_V1_Value()
                for entry in json.entries {
                    if let data = Data(base64Encoded: entry.value) {
                        value.entries["value"] = data
                    }
                }
                response.contents = .value(value)
                response.outcome = .success
            } else {
                response.outcome = .keyNotFound
            }
        } catch let error {
            var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
            responseError.description_p = error.localizedDescription
            response.outcome = .keyNotFound
        }
        
        return response
    }
}
