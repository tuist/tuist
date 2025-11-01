import CryptoKit
@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Logging
import Path
import TuistServer
import libzstd

public struct CASService: CompilationCacheService_Cas_V1_CASDBService.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let saveCacheCASService: SaveCacheCASServicing
    private let loadCacheCASService: LoadCacheCASServicing
    private let fileSystem: FileSysteming

    public init(
        fullHandle: String,
        serverURL: URL,
        saveCacheCASService: SaveCacheCASServicing = SaveCacheCASService(),
        loadCacheCASService: LoadCacheCASServicing = LoadCacheCASService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.saveCacheCASService = saveCacheCASService
        self.loadCacheCASService = loadCacheCASService
        self.fileSystem = fileSystem
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
            let compressedData = try await loadCacheCASService.loadCacheCAS(
                casId: casID,
                fullHandle: fullHandle,
                serverURL: serverURL
            )

            // Decompress the data using zstd
            let decompressedData: Data
            do {
                // Get the decompressed size first
                let decompressedSize = compressedData.withUnsafeBytes { bytes in
                    ZSTD_getFrameContentSize(bytes.baseAddress, compressedData.count)
                }
                
                guard decompressedSize != ZSTD_CONTENTSIZE_ERROR && decompressedSize != ZSTD_CONTENTSIZE_UNKNOWN else {
                    throw NSError(domain: "ZSTDError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Cannot determine decompressed size"])
                }
                
                var decompressedBuffer = Array<UInt8>(repeating: 0, count: Int(decompressedSize))
                
                let actualDecompressedSize = compressedData.withUnsafeBytes { srcBytes in
                    decompressedBuffer.withUnsafeMutableBytes { dstBytes in
                        ZSTD_decompress(
                            dstBytes.baseAddress,
                            Int(decompressedSize),
                            srcBytes.baseAddress,
                            compressedData.count
                        )
                    }
                }
                
                guard ZSTD_isError(actualDecompressedSize) == 0 else {
                    throw NSError(domain: "ZSTDError", code: Int(actualDecompressedSize), userInfo: [NSLocalizedDescriptionKey: "Decompression failed"])
                }
                
                decompressedData = Data(decompressedBuffer.prefix(Int(actualDecompressedSize)))
                Logger.current.debug("CAS.load decompressed data from \(compressedData.count) to \(decompressedData.count) bytes")
            } catch {
                Logger.current.error("CAS.load failed to decompress data: \(error)")
                response.outcome = .error
                var responseError = CompilationCacheService_Cas_V1_ResponseError()
                responseError.description_p = "Failed to decompress data: \(error.localizedDescription)"
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

        // Compress the data using zstd
        let compressedData: Data
        do {
            let maxCompressedSize = ZSTD_compressBound(data.count)
            var compressedBuffer = Array<UInt8>(repeating: 0, count: maxCompressedSize)
            
            let compressedSize = data.withUnsafeBytes { srcBytes in
                compressedBuffer.withUnsafeMutableBytes { dstBytes in
                    ZSTD_compress(
                        dstBytes.baseAddress,
                        maxCompressedSize,
                        srcBytes.baseAddress,
                        data.count,
                        1 // compression level
                    )
                }
            }
            
            guard ZSTD_isError(compressedSize) == 0 else {
                throw NSError(domain: "ZSTDError", code: Int(compressedSize), userInfo: [NSLocalizedDescriptionKey: "Compression failed"])
            }
            
            compressedData = Data(compressedBuffer.prefix(compressedSize))
            Logger.current.debug("CAS.save compressed data from \(data.count) to \(compressedData.count) bytes")
        } catch {
            Logger.current.error("CAS.save failed to compress data: \(error)")
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = "Failed to compress data: \(error.localizedDescription)"
            response.error = responseError
            response.contents = .error(responseError)
            return response
        }

        let hash = SHA256.hash(data: data)
        let fingerprint = hash.compactMap { String(format: "%02X", $0) }.joined()

        var message = CompilationCacheService_Cas_V1_CASDataID()
        message.id = fingerprint.data(using: .utf8)!

        Logger.current.debug("CAS.save computed fingerprint: \(fingerprint), original size: \(data.count) bytes, compressed size: \(compressedData.count) bytes")

        do {
            try await saveCacheCASService.saveCacheCAS(
                compressedData,
                casId: fingerprint,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            response.casID = message
            response.contents = .casID(message)

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
