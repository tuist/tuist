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
        let startTime = Date()
        let casID = converKeyToCasID(request.key)
        let keySize = request.key.count
        let entriesCount = request.value.entries.count
        let totalValueSize = request.value.entries.values.reduce(0) { $0 + $1.count }

        Logger.current
            .debug(
                "KeyValue.putValue starting - key size: \(keySize) bytes, entries: \(entriesCount), total value size: \(totalValueSize) bytes, casID: \(casID)"
            )

        // Convert protobuf entries to [String: String] format
        var entries: [String: String] = [:]
        for (key, data) in request.value.entries {
            entries[key] = data.base64EncodedString()
        }

        var response = CompilationCacheService_Keyvalue_V1_PutValueResponse()

        // Capture the logger before creating the Task
        let logger = Logger.current

        // Return success immediately and fire the API call in the background
        Task {
            do {
                try await putCacheValueService.putCacheValue(
                    casId: casID,
                    entries: entries,
                    fullHandle: fullHandle,
                    serverURL: serverURL
                )
                let duration = Date().timeIntervalSince(startTime)
                logger
                    .debug(
                        "KeyValue.putValue background upload completed successfully in \(String(format: "%.3f", duration))s for casID: \(casID)"
                    )
            } catch {
                let duration = Date().timeIntervalSince(startTime)
                logger
                    .error(
                        "KeyValue.putValue background upload failed after \(String(format: "%.3f", duration))s for casID: \(casID): \(error.userFriendlyDescription())"
                    )
            }
        }

        Logger.current.debug("KeyValue.putValue returning immediately for casID: \(casID)")
        return response
    }

    public func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        let startTime = Date()
        let casID = converKeyToCasID(request.key)
        let keySize = request.key.count

        Logger.current.debug("KeyValue.getValue starting - key size: \(keySize) bytes, casID: \(casID)")

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

                let duration = Date().timeIntervalSince(startTime)
                let valueSize = value.entries.values.reduce(0) { $0 + $1.count }
                Logger.current
                    .debug(
                        "KeyValue.getValue completed successfully in \(String(format: "%.3f", duration))s - found value with size: \(valueSize) bytes for casID: \(casID)"
                    )
            } else {
                response.outcome = .keyNotFound
                let duration = Date().timeIntervalSince(startTime)
                Logger.current
                    .debug(
                        "KeyValue.getValue completed in \(String(format: "%.3f", duration))s - key not found for casID: \(casID)"
                    )
            }
        } catch {
            var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
            responseError.description_p = error.userFriendlyDescription()
            response.error = responseError
            response.outcome = .keyNotFound

            let duration = Date().timeIntervalSince(startTime)
            Logger.current
                .error("KeyValue.getValue failed after \(String(format: "%.3f", duration))s for casID: \(casID): \(error)")
        }

        return response
    }

    private func converKeyToCasID(_ key: Data) -> String {
        "0~" + key.dropFirst().base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
