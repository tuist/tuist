import CryptoKit
@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Logging
import Path
import TuistCASAnalytics
import TuistServer

public struct CASService: CompilationCacheService_Cas_V1_CASDBService.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let saveCacheCASService: SaveCacheCASServicing
    private let loadCacheCASService: LoadCacheCASServicing
    private let fileSystem: FileSysteming
    private let metadataStore: CASTaskMetadataStoring

    public init(
        fullHandle: String,
        serverURL: URL,
        saveCacheCASService: SaveCacheCASServicing = SaveCacheCASService(),
        loadCacheCASService: LoadCacheCASServicing = LoadCacheCASService(),
        fileSystem: FileSysteming = FileSystem(),
        metadataStore: CASTaskMetadataStoring = FileCASTaskMetadataStore()
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.saveCacheCASService = saveCacheCASService
        self.loadCacheCASService = loadCacheCASService
        self.fileSystem = fileSystem
        self.metadataStore = metadataStore
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
            let data = try await loadCacheCASService.loadCacheCAS(
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

            // Store metadata for the load operation in background
            Task {
                let metadata = CASTaskMetadata(size: data.count)
                do {
                    try await metadataStore.storeMetadata(metadata, for: casID)
                } catch {
                    Logger.current.error("Failed to store CAS load metadata for casID: \(casID): \(error)")
                }
            }

            let duration = ProcessInfo.processInfo.systemUptime - startTime
            Logger.current
                .debug(
                    "CAS.load completed successfully in \(String(format: "%.3f", duration))s - loaded \(data.count) bytes for casID: \(casID)"
                )
        } catch {
            response.outcome = .error
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = error.userFriendlyDescription()
            response.error = responseError
            response.contents = .error(responseError)

            let duration = ProcessInfo.processInfo.systemUptime - startTime
            Logger.current.error("CAS.load failed after \(String(format: "%.3f", duration))s for casID: \(casID): \(error)")
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
            Logger.current.debug("CAS.save starting - reading from file: \(request.data.blob.filePath)")
            do {
                let absolutePath = try AbsolutePath(validating: request.data.blob.filePath)
                data = try await fileSystem.readFile(at: absolutePath)
            } catch {
                var responseError = CompilationCacheService_Cas_V1_ResponseError()
                responseError.description_p = error.userFriendlyDescription()
                response.error = responseError
                response.contents = .error(responseError)
                Logger.current.error("CAS.save failed to read file \(request.data.blob.filePath): \(error)")
                return response
            }
        } else {
            data = request.data.blob.data
            Logger.current.debug("CAS.save starting - data size: \(data.count) bytes")
        }

        let hash = SHA256.hash(data: data)
        let fingerprint = hash.compactMap { String(format: "%02X", $0) }.joined()

        var message = CompilationCacheService_Cas_V1_CASDataID()
        message.id = fingerprint.data(using: .utf8)!

        Logger.current.debug("CAS.save computed fingerprint: \(fingerprint), data size: \(data.count) bytes")

        do {
            try await saveCacheCASService.saveCacheCAS(
                data,
                casId: fingerprint,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            response.casID = message
            response.contents = .casID(message)

            // Store metadata for the save operation in background
            Task {
                let metadata = CASTaskMetadata(size: data.count)
                do {
                    try await metadataStore.storeMetadata(metadata, for: fingerprint)
                } catch {
                    Logger.current.error("Failed to store CAS save metadata for fingerprint: \(fingerprint): \(error)")
                }
            }

            let duration = ProcessInfo.processInfo.systemUptime - startTime
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
}
