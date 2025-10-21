@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Path
import TuistServer

public struct KeyValueService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let putCacheValueService: PutCacheValueServicing
    private let getCacheValueService: GetCacheValueServicing

    public init(
        fullHandle: String,
        serverURL: URL,
        putCacheValueService: PutCacheValueServicing = PutCacheValueService(),
        getCacheValueService: GetCacheValueServicing = GetCacheValueService()
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.putCacheValueService = putCacheValueService
        self.getCacheValueService = getCacheValueService
    }

    public func putValue(
        request: CompilationCacheService_Keyvalue_V1_PutValueRequest,
        context _: ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        let casID = converKeyToCasID(request.key)

        // Convert protobuf entries to [String: String] format
        var entries: [String: String] = [:]
        for (key, data) in request.value.entries {
            entries[key] = data.base64EncodedString()
        }

        var response = CompilationCacheService_Keyvalue_V1_PutValueResponse()
        do {
            try await putCacheValueService.putCacheValue(
                casId: casID,
                entries: entries,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            return response
        } catch {
            var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
            responseError.description_p = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            response.error = responseError
            return response
        }
    }

    public func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        let casID = converKeyToCasID(request.key)

        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()

        do {
            if let json = try await getCacheValueService.getCacheValue(
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
        } catch {
            var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
            responseError.description_p = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            response.error = responseError
            response.outcome = .keyNotFound
        }

        return response
    }

    private func converKeyToCasID(_ key: Data) -> String {
        "0~" + key.dropFirst().base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
