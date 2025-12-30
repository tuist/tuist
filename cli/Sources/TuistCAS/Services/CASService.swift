import CryptoKit
@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Logging
import Path
import TuistCache
import TuistCASAnalytics
import TuistServer

public struct CASService: CompilationCacheService_Cas_V1_CASDBService.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let cacheURLStore: CacheURLStoring
    private let saveCacheCASService: SaveCacheCASServicing
    private let loadCacheCASService: LoadCacheCASServicing
    private let fileSystem: FileSysteming
    private let metadataStore: CASOutputMetadataStoring
    private let dataCompressingService: DataCompressingServicing
    private let serverAuthenticationController: ServerAuthenticationControlling

    private var accountHandle: String? {
        fullHandle.split(separator: "/").first.map(String.init)
    }

    public init(
        fullHandle: String,
        serverURL: URL,
        cacheURLStore: CacheURLStoring
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.cacheURLStore = cacheURLStore
        saveCacheCASService = SaveCacheCASService()
        loadCacheCASService = LoadCacheCASService()
        fileSystem = FileSystem()
        dataCompressingService = DataCompressingService()
        metadataStore = CASOutputMetadataStore()
        serverAuthenticationController = ServerAuthenticationController()
    }

    init(
        fullHandle: String,
        serverURL: URL,
        cacheURLStore: CacheURLStoring,
        saveCacheCASService: SaveCacheCASServicing,
        loadCacheCASService: LoadCacheCASServicing,
        fileSystem: FileSysteming,
        dataCompressingService: DataCompressingServicing,
        metadataStore: CASOutputMetadataStoring,
        serverAuthenticationController: ServerAuthenticationControlling
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.cacheURLStore = cacheURLStore
        self.saveCacheCASService = saveCacheCASService
        self.loadCacheCASService = loadCacheCASService
        self.fileSystem = fileSystem
        self.metadataStore = metadataStore
        self.dataCompressingService = dataCompressingService
        self.serverAuthenticationController = serverAuthenticationController
    }

    public func load(
        request: CompilationCacheService_Cas_V1_CASLoadRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASLoadResponse {
        let startTime = ProcessInfo.processInfo.systemUptime
        var response = CompilationCacheService_Cas_V1_CASLoadResponse()

        guard let casID = String(data: request.casID.id, encoding: .utf8) else {
            response.outcome = .error
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = "Invalid CAS ID: Unable to decode CAS ID as UTF-8 string"
            response.error = responseError
            response.contents = .error(responseError)
            Logger.current.error("CAS.load failed - invalid CAS ID (unable to decode as UTF-8)")
            return response
        }

        Logger.current.debug("CAS.load starting - casID: \(casID)")

        do {
            let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
            let compressedData = try await loadCacheCASService.loadCacheCAS(
                casId: casID,
                fullHandle: fullHandle,
                serverURL: cacheURL,
                authenticationURL: serverURL,
                serverAuthenticationController: serverAuthenticationController
            )

            let decompressedData: Data
            do {
                decompressedData = try await dataCompressingService.decompress(compressedData)
            } catch {
                Logger.current.error("CAS.load failed to decompress data: \(error)")
                response.outcome = .error
                var responseError = CompilationCacheService_Cas_V1_ResponseError()
                responseError.description_p = error.userFriendlyDescription()
                response.error = responseError
                response.contents = .error(responseError)
                return response
            }

            var bytes = CompilationCacheService_Cas_V1_CASBytes()
            bytes.data = decompressedData

            var blob = CompilationCacheService_Cas_V1_CASBlob()
            blob.blob = bytes

            response.contents = .data(blob)
            response.outcome = .success

            let duration = ProcessInfo.processInfo.systemUptime - startTime

            storeMetadata(
                size: decompressedData.count,
                compressedSize: compressedData.count,
                duration: duration * 1000,
                for: casID
            )
            Logger.current
                .debug(
                    "CAS.load completed successfully in \(String(format: "%.3f", duration))s - loaded \(compressedData.count) compressed bytes, decompressed to \(decompressedData.count) bytes for casID: \(casID)"
                )
        } catch {
            response.outcome = .error
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = error.userFriendlyDescription()
            response.error = responseError
            response.contents = .error(responseError)

            let duration = ProcessInfo.processInfo.systemUptime - startTime
            Logger.current.error(
                "CAS.load failed after \(String(format: "%.3f", duration))s for casID: \(casID): \(error)"
            )
        }

        return response
    }

    public func save(
        request: CompilationCacheService_Cas_V1_CASSaveRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASSaveResponse {
        let startTime = ProcessInfo.processInfo.systemUptime
        var response = CompilationCacheService_Cas_V1_CASSaveResponse()

        let data: Data
        let isFilePath = !request.data.blob.filePath.isEmpty

        if isFilePath {
            Logger.current.debug(
                "CAS.save starting - reading from file: \(request.data.blob.filePath)"
            )
            do {
                let absolutePath = try AbsolutePath(validating: request.data.blob.filePath)
                data = try await fileSystem.readFile(at: absolutePath)
            } catch {
                var responseError = CompilationCacheService_Cas_V1_ResponseError()
                responseError.description_p = error.userFriendlyDescription()
                response.error = responseError
                response.contents = .error(responseError)
                Logger.current.error(
                    "CAS.save failed to read file \(request.data.blob.filePath): \(error)"
                )
                return response
            }
        } else {
            data = request.data.blob.data
            Logger.current.debug("CAS.save starting - data size: \(data.count) bytes")
        }

        let compressedData: Data
        do {
            compressedData = try await dataCompressingService.compress(data)
        } catch {
            Logger.current.error("CAS.save failed to compress data: \(error)")
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = "Failed to compress data: \(error.localizedDescription)"
            response.error = responseError
            response.contents = .error(responseError)
            return response
        }

        let dataWithVersion = data + "cache-v1".data(using: .utf8)!
        let hash = SHA256.hash(data: dataWithVersion)
        let fingerprint = hash.compactMap { String(format: "%02X", $0) }.joined()

        var message = CompilationCacheService_Cas_V1_CASDataID()
        message.id = fingerprint.data(using: .utf8)!

        Logger.current
            .debug(
                "CAS.save computed fingerprint: \(fingerprint), original size: \(data.count) bytes, compressed size: \(compressedData.count) bytes"
            )

        do {
            let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
            try await saveCacheCASService.saveCacheCAS(
                compressedData,
                casId: fingerprint,
                fullHandle: fullHandle,
                serverURL: cacheURL,
                authenticationURL: serverURL,
                serverAuthenticationController: serverAuthenticationController
            )
            response.casID = message
            response.contents = .casID(message)

            let duration = ProcessInfo.processInfo.systemUptime - startTime

            storeMetadata(
                size: data.count,
                compressedSize: compressedData.count,
                duration: duration * 1000,
                for: fingerprint
            )
            Logger.current
                .debug(
                    "CAS.save completed successfully in \(String(format: "%.3f", duration))s for fingerprint: \(fingerprint)"
                )
        } catch {
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = error.userFriendlyDescription()
            response.error = responseError
            response.contents = .error(responseError)

            let duration = ProcessInfo.processInfo.systemUptime - startTime
            Logger.current
                .error(
                    "CAS.save failed after \(String(format: "%.3f", duration))s for fingerprint: \(fingerprint): \(error.userFriendlyDescription())"
                )
        }

        return response
    }

    public func put(
        request _: CompilationCacheService_Cas_V1_CASPutRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASPutResponse {
        var response = CompilationCacheService_Cas_V1_CASPutResponse()
        var responseError = CompilationCacheService_Cas_V1_ResponseError()
        responseError.description_p = "Method 'put' is not implemented"
        response.error = responseError
        response.contents = .error(responseError)
        return response
    }

    public func get(
        request _: CompilationCacheService_Cas_V1_CASGetRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASGetResponse {
        var response = CompilationCacheService_Cas_V1_CASGetResponse()
        var responseError = CompilationCacheService_Cas_V1_ResponseError()
        responseError.description_p = "Method 'get' is not implemented"
        response.error = responseError
        response.contents = .error(responseError)
        return response
    }

    private func storeMetadata(
        size: Int,
        compressedSize: Int,
        duration: TimeInterval,
        for casID: String
    ) {
        Task {
            let metadata = CASOutputMetadata(
                size: size,
                duration: duration,
                compressedSize: compressedSize
            )
            do {
                try await metadataStore.storeMetadata(metadata, for: casID)
            } catch {
                Logger.current.error(
                    "Failed to store CAS metadata for casID: \(casID): \(error)"
                )
            }
        }
    }
}
