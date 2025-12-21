@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Logging
import Path
import TuistCache
import TuistCASAnalytics
import TuistServer
import TuistSupport

public struct KeyValueService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let cacheURLStore: CacheURLStoring
    private let putCacheValueService: PutCacheValueServicing
    private let getCacheValueService: GetCacheValueServicing
    private let fileSystem: FileSystem
    private let nodeStore: CASNodeStoring
    private let metadataStore: KeyValueMetadataStoring
    private let serverAuthenticationController: ServerAuthenticationControlling

    private var accountHandle: String? {
        fullHandle.split(separator: "/").first.map(String.init)
    }

    public init(
        fullHandle: String,
        serverURL: URL,
        cacheURLStore: CacheURLStoring,
        putCacheValueService: PutCacheValueServicing = PutCacheValueService(),
        getCacheValueService: GetCacheValueServicing = GetCacheValueService(),
        fileSystem: FileSystem = FileSystem(),
        nodeStore: CASNodeStoring = CASNodeStore(),
        metadataStore: KeyValueMetadataStoring = KeyValueMetadataStore(),
        serverAuthenticationController: ServerAuthenticationControlling = ServerAuthenticationController()
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.cacheURLStore = cacheURLStore
        self.putCacheValueService = putCacheValueService
        self.getCacheValueService = getCacheValueService
        self.fileSystem = fileSystem
        self.nodeStore = nodeStore
        self.metadataStore = metadataStore
        self.serverAuthenticationController = serverAuthenticationController
    }

    public func putValue(
        request: CompilationCacheService_Keyvalue_V1_PutValueRequest,
        context _: ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        let startTime = ProcessInfo.processInfo.systemUptime
        let casID = convertKeyToCasID(request.key)
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
            let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
            try await putCacheValueService.putCacheValue(
                casId: casID,
                entries: entries,
                fullHandle: fullHandle,
                serverURL: cacheURL,
                authenticationURL: serverURL,
                serverAuthenticationController: serverAuthenticationController
            )

            Task {
                for (_, data) in request.value.entries {
                    await parseAndStoreCASNodes(from: data)
                }
            }

            let duration = ProcessInfo.processInfo.systemUptime - startTime

            storeMetadata(
                duration: duration * 1000,
                for: casID,
                operationType: .write
            )

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
        let casID = convertKeyToCasID(request.key)
        let keySize = request.key.count

        Logger.current.debug("KeyValue.getValue starting - key size: \(keySize) bytes, casID: \(casID)")

        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
        let duration: TimeInterval

        do {
            let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
            if let json = try await getCacheValueService.getCacheValue(
                casId: casID,
                fullHandle: fullHandle,
                serverURL: cacheURL,
                authenticationURL: serverURL,
                serverAuthenticationController: serverAuthenticationController
            ) {
                var value = CompilationCacheService_Keyvalue_V1_Value()

                for entry in json.entries {
                    if let data = Data(base64Encoded: entry.value) {
                        value.entries["value"] = data

                        Task {
                            await parseAndStoreCASNodes(from: data)
                        }
                    }
                }

                response.contents = .value(value)
                response.outcome = .success

                duration = ProcessInfo.processInfo.systemUptime - startTime

                let valueSize = value.entries.values.reduce(0) { $0 + $1.count }
                Logger.current
                    .debug(
                        "KeyValue.getValue completed successfully in \(String(format: "%.3f", duration))s - found value with size: \(valueSize) bytes for casID: \(casID)"
                    )
            } else {
                response.outcome = .keyNotFound
                duration = ProcessInfo.processInfo.systemUptime - startTime
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

            duration = ProcessInfo.processInfo.systemUptime - startTime
            Logger.current
                .error("KeyValue.getValue failed after \(String(format: "%.3f", duration))s for casID: \(casID): \(error)")
        }

        storeMetadata(
            duration: duration * 1000,
            for: casID,
            operationType: .read
        )

        return response
    }

    private func convertKeyToCasID(_ key: Data) -> String {
        "0~" + key.dropFirst().base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }

    /// For each CAS node, we need to know what CAS checksums it relates to for CAS analytics.
    /// This parsing is a bit tricky. Ideally, we would have a more type-safe way to parse this, but the way entry is encoded is
    /// done in the closed source CAS plugin.
    /// We could use the following command, but that would require us to rehash all the content, making the analysis slow:
    /// ```
    /// /Applications/Xcode-26.0.1.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/llvm-cas
    /// --fcas - plugin - path = "/Applications/Xcode-26.0.1.app/Contents/Developer/usr/lib/libToolchainCASPlugin.dylib"
    /// --cas = "/Users/marekfort/Library/Developer/Xcode/DerivedData/CompilationCache.noindex/plugin" --cat - node - data
    /// "0~DsrOlkm-YT-52KKLfjpp4DaFdCZH6diFHz2CENsVN4SDon18_MT4ovquwH1BbkLmCaL597K3hbuINRUqRTuIgw=="
    /// ```
    private func parseAndStoreCASNodes(from data: Data) async {
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
                        try await nodeStore.storeNode(nodeID, checksum: hexString.uppercased())
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

    private func storeMetadata(
        duration: TimeInterval,
        for cacheKey: String,
        operationType: KeyValueOperationType
    ) {
        Task {
            let metadata = KeyValueMetadata(duration: duration)
            do {
                try await metadataStore.storeMetadata(metadata, for: cacheKey, operationType: operationType)
            } catch {
                Logger.current.error(
                    "Failed to store KeyValue metadata for cacheKey: \(cacheKey): \(error)"
                )
            }
        }
    }
}
