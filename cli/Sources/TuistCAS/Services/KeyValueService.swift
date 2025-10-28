@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Path
import TuistServer
import TuistSupport

public struct KeyValueService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let putCacheValueService: PutCacheValueServicing
    private let getCacheValueService: GetCacheValueServicing
    private let fileSystem: FileSystem
    private let environment: Environmenting

    public init(
        fullHandle: String,
        serverURL: URL,
        putCacheValueService: PutCacheValueServicing = PutCacheValueService(),
        getCacheValueService: GetCacheValueServicing = GetCacheValueService(),
        fileSystem: FileSystem = FileSystem(),
        environment: Environmenting = Environment.current
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.putCacheValueService = putCacheValueService
        self.getCacheValueService = getCacheValueService
        self.fileSystem = fileSystem
        self.environment = environment
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
            responseError.description_p = error.userFriendlyDescription()
            response.error = responseError
            return response
        }
    }

    public func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        let casID = converKeyToCasID(request.key)
        print(request.key)

        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()

        do {
            if let json = try await getCacheValueService.getCacheValue(
                casId: casID,
                fullHandle: fullHandle,
                serverURL: serverURL
            ) {
                var value = CompilationCacheService_Keyvalue_V1_Value()
                
                // Store entry keys for cache analysis
                // The entry.value is actually the key (e.g., "0~...") that will appear in 
                // "Swift caching materialize outputs from 0~..." build steps
                var entryKeys: [String] = []
                
                for entry in json.entries {
                    if let data = Data(base64Encoded: entry.value) {
                        value.entries["value"] = data
                        // The value IS the entry key used in materialize steps
                        entryKeys.append(entry.value)
                    }
                }
                
                // Save the entry keys to a JSON file asynchronously (non-blocking)
                Task {
                    do {
                        try await saveKeyValueEntries(key: casID, entryKeys: entryKeys)
                    } catch {
                        // Log error but don't fail the request
                        print("Failed to save keyvalue entries for \(casID): \(error)")
                    }
                }
                
                response.contents = .value(value)
                response.outcome = .success
            } else {
                response.outcome = .keyNotFound
            }
        } catch {
            var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
            responseError.description_p = error.userFriendlyDescription()
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
    
    private func saveKeyValueEntries(key: String, entryKeys: [String]) async throws {
        let keyValueEntriesDirectory = environment.cacheDirectory.appending(component: "keyvalue-entries")
        
        // Create directory if it doesn't exist
        if try await !fileSystem.exists(keyValueEntriesDirectory) {
            try await fileSystem.makeDirectory(at: keyValueEntriesDirectory)
        }
        
        // Create a JSON file for this key
        let jsonPath = keyValueEntriesDirectory.appending(component: "\(key).json")
        
        // Create the JSON structure
        let jsonData = try JSONEncoder().encode(entryKeys)
        
        // Write to file
        try jsonData.write(to: jsonPath.url)
    }
}
