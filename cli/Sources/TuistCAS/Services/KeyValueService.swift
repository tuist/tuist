@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Logging
import Path
import TuistCASAnalytics
import TuistServer
import TuistSupport

public struct KeyValueService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let putCacheValueService: PutCacheValueServicing
    private let getCacheValueService: GetCacheValueServicing
    private let fileSystem: FileSystem
    private let nodeMappingStore: CASNodeMappingStoring

    public init(
        fullHandle: String,
        serverURL: URL,
        putCacheValueService: PutCacheValueServicing = PutCacheValueService(),
        getCacheValueService: GetCacheValueServicing = GetCacheValueService(),
        fileSystem: FileSystem = FileSystem(),
        nodeMappingStore: CASNodeMappingStoring = FileCASNodeMappingStore()
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.putCacheValueService = putCacheValueService
        self.getCacheValueService = getCacheValueService
        self.fileSystem = fileSystem
        self.nodeMappingStore = nodeMappingStore
    }

    public func putValue(
        request: CompilationCacheService_Keyvalue_V1_PutValueRequest,
        context _: ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        let startTime = ProcessInfo.processInfo.systemUptime
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
        do {
            try await putCacheValueService.putCacheValue(
                casId: casID,
                entries: entries,
                fullHandle: fullHandle,
                serverURL: serverURL
            )

            let duration = ProcessInfo.processInfo.systemUptime - startTime
            Logger.current
                .debug(
                    "KeyValue.putValue completed successfully in \(String(format: "%.3f", duration))s for casID: \(casID)"
                )

            return response
        } catch {
            var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
            responseError.description_p = error.userFriendlyDescription()
            response.error = responseError

            let duration = ProcessInfo.processInfo.systemUptime - startTime
            Logger.current
                .error(
                    "KeyValue.putValue failed after \(String(format: "%.3f", duration))s for casID: \(casID): \(error.userFriendlyDescription())"
                )

            return response
        }
    }

    public func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        let startTime = ProcessInfo.processInfo.systemUptime
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

                        // Parse and store node ID to checksum mappings
                        await parseAndStoreMappings(from: data)
                    }
                }

                response.contents = .value(value)
                response.outcome = .success

                let duration = ProcessInfo.processInfo.systemUptime - startTime
                let valueSize = value.entries.values.reduce(0) { $0 + $1.count }
                Logger.current
                    .debug(
                        "KeyValue.getValue completed successfully in \(String(format: "%.3f", duration))s - found value with size: \(valueSize) bytes for casID: \(casID)"
                    )
            } else {
                response.outcome = .keyNotFound
                let duration = ProcessInfo.processInfo.systemUptime - startTime
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

            let duration = ProcessInfo.processInfo.systemUptime - startTime
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

    /// Parse CompileJobResultResponse data and store node ID to checksum mappings
    private func parseAndStoreMappings(from data: Data) async {
        var offset = 0

        // Skip metadata at the beginning and look for CAS entries
        while offset < data.count {
            // Look for the pattern that indicates a CAS entry
            // Each entry starts with protobuf field markers, then has:
            // - 0x0A 0x41 0x00 (field + length + CAS ID marker)
            // - 64 bytes of CAS ID
            // - 0x12 0x40 (field + length for hex)
            // - 64 bytes of hex checksum

            if let entryInfo = findNextCASEntry(in: data, startingAt: offset) {
                let (casOffset, hexOffset, nextOffset) = entryInfo

                // Extract CAS ID (64 bytes)
                let casIDData = data.subdata(in: casOffset ..< (casOffset + 64))

                // Extract hex checksum (64 bytes)
                let hexData = data.subdata(in: hexOffset ..< (hexOffset + 64))

                if let hexString = String(data: hexData, encoding: .ascii),
                   hexString.count == 64,
                   isValidHex(hexString)
                {
                    // Convert CAS ID to node ID format
                    let nodeIDBase64URL = casIDData.base64EncodedString()
                        .replacingOccurrences(of: "+", with: "-")
                        .replacingOccurrences(of: "/", with: "_")
                    let nodeID = "0~\(nodeIDBase64URL)"

                    // Store the mapping
                    do {
                        try await nodeMappingStore.storeNode(nodeID, checksum: hexString.uppercased())
                    } catch {
                        Logger.current.error("Failed to store node mapping: \(error)")
                    }
                }

                offset = nextOffset
            } else {
                break
            }
        }
    }

    /// Find the next CAS entry in the data
    private func findNextCASEntry(in data: Data, startingAt offset: Int) -> (casOffset: Int, hexOffset: Int, nextOffset: Int)? {
        var searchOffset = offset

        // Look for the CAS ID pattern: 0x0A 0x41 0x00
        while searchOffset + 67 < data.count { // Need at least 3 + 64 bytes
            if data[searchOffset] == 0x0A,
               data[searchOffset + 1] == 0x41,
               data[searchOffset + 2] == 0x00
            {
                let casOffset = searchOffset + 3 // Skip the 0x0A 0x41 0x00
                let hexSearchStart = casOffset + 64

                // Look for hex pattern: 0x12 0x40 (field + 64-byte length)
                if hexSearchStart + 2 < data.count,
                   data[hexSearchStart] == 0x12,
                   data[hexSearchStart + 1] == 0x40
                {
                    let hexOffset = hexSearchStart + 2
                    let nextOffset = hexOffset + 64

                    return (casOffset: casOffset, hexOffset: hexOffset, nextOffset: nextOffset)
                }
            }
            searchOffset += 1
        }

        return nil
    }

    /// Check if string is valid hex
    private func isValidHex(_ str: String) -> Bool {
        let hexChars = Set("0123456789ABCDEFabcdef")
        return str.allSatisfy { hexChars.contains($0) }
    }
}
