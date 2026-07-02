#if os(macOS)
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
        private let analyticsDatabase: CASAnalyticsDatabasing
        private let dataCompressingService: DataCompressingServicing
        private let serverAuthenticationController: ServerAuthenticationControlling
        private let upload: Bool
        private let circuitBreaker: CASCircuitBreaker

        private var accountHandle: String? {
            fullHandle.split(separator: "/").first.map(String.init)
        }

        public init(
            fullHandle: String,
            serverURL: URL,
            cacheURLStore: CacheURLStoring,
            upload: Bool = true,
            analyticsDatabase: CASAnalyticsDatabasing
        ) {
            self.fullHandle = fullHandle
            self.serverURL = serverURL
            self.cacheURLStore = cacheURLStore
            self.upload = upload
            saveCacheCASService = SaveCacheCASService()
            loadCacheCASService = LoadCacheCASService()
            fileSystem = FileSystem()
            dataCompressingService = DataCompressingService()
            self.analyticsDatabase = analyticsDatabase
            serverAuthenticationController = ServerAuthenticationController()
            circuitBreaker = CASCircuitBreaker()
        }

        init(
            fullHandle: String,
            serverURL: URL,
            cacheURLStore: CacheURLStoring,
            saveCacheCASService: SaveCacheCASServicing,
            loadCacheCASService: LoadCacheCASServicing,
            fileSystem: FileSysteming,
            dataCompressingService: DataCompressingServicing,
            analyticsDatabase: CASAnalyticsDatabasing,
            serverAuthenticationController: ServerAuthenticationControlling,
            upload: Bool = true,
            circuitBreaker: CASCircuitBreaker = CASCircuitBreaker()
        ) {
            self.fullHandle = fullHandle
            self.serverURL = serverURL
            self.cacheURLStore = cacheURLStore
            self.saveCacheCASService = saveCacheCASService
            self.loadCacheCASService = loadCacheCASService
            self.fileSystem = fileSystem
            self.analyticsDatabase = analyticsDatabase
            self.dataCompressingService = dataCompressingService
            self.serverAuthenticationController = serverAuthenticationController
            self.upload = upload
            self.circuitBreaker = circuitBreaker
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

            guard await circuitBreaker.shouldAttempt() else {
                Logger.current.debug("CAS.load skipping remote cache (circuit open) - casID: \(casID)")
                response.outcome = .error
                var responseError = CompilationCacheService_Cas_V1_ResponseError()
                responseError.description_p = "Remote cache unavailable; building locally."
                response.error = responseError
                response.contents = .error(responseError)
                return response
            }

            do {
                let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
                let fetchStart = ProcessInfo.processInfo.systemUptime
                let compressedData = try await loadCacheCASService.loadCacheCAS(
                    casId: casID,
                    fullHandle: fullHandle,
                    serverURL: cacheURL,
                    authenticationURL: serverURL,
                    serverAuthenticationController: serverAuthenticationController
                )
                let transferDuration = ProcessInfo.processInfo.systemUptime - fetchStart
                await circuitBreaker.recordSuccess()

                let decompressedData: Data
                let codecDuration: TimeInterval
                do {
                    let decompressStart = ProcessInfo.processInfo.systemUptime
                    decompressedData = try await dataCompressingService.decompress(compressedData)
                    codecDuration = ProcessInfo.processInfo.systemUptime - decompressStart
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
                    transferDuration: transferDuration * 1000,
                    codecDuration: codecDuration * 1000,
                    for: casID
                )
                Logger.current
                    .debug(
                        "CAS.load completed successfully in \(String(format: "%.3f", duration))s - loaded \(compressedData.count) compressed bytes, decompressed to \(decompressedData.count) bytes for casID: \(casID)"
                    )
            } catch {
                if casErrorIsBackendHealthy(error) {
                    await circuitBreaker.recordSuccess()
                } else {
                    await circuitBreaker.recordFailure()
                }
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

            // The fingerprint is derived from the raw data, so compute it first
            // (cheap) and only compress (expensive) once we know an upload will
            // actually be attempted. When there is nothing to upload to — upload
            // disabled, or the circuit open because the remote cache is unavailable
            // — the artifact is already built locally, so paying the zstd
            // compression per artifact would defeat the fast fallback.
            let dataWithVersion = data + "cache-v1".data(using: .utf8)!
            let hash = SHA256.hash(data: dataWithVersion)
            let fingerprint = hash.compactMap { String(format: "%02X", $0) }.joined()

            var message = CompilationCacheService_Cas_V1_CASDataID()
            message.id = fingerprint.data(using: .utf8)!

            if !upload {
                Logger.current.debug("CAS.save skipping upload (upload disabled) for fingerprint: \(fingerprint)")
                response.casID = message
                response.contents = .casID(message)
                return response
            }

            if await circuitBreaker.isOpen {
                Logger.current.debug("CAS.save skipping upload (circuit open) for fingerprint: \(fingerprint)")
                response.casID = message
                response.contents = .casID(message)
                return response
            }

            let compressedData: Data
            let codecDuration: TimeInterval
            do {
                let compressStart = ProcessInfo.processInfo.systemUptime
                compressedData = try await dataCompressingService.compress(data)
                codecDuration = ProcessInfo.processInfo.systemUptime - compressStart
            } catch {
                Logger.current.error("CAS.save failed to compress data: \(error)")
                var responseError = CompilationCacheService_Cas_V1_ResponseError()
                responseError.description_p = "Failed to compress data: \(error.localizedDescription)"
                response.error = responseError
                response.contents = .error(responseError)
                return response
            }

            Logger.current
                .debug(
                    "CAS.save computed fingerprint: \(fingerprint), original size: \(data.count) bytes, compressed size: \(compressedData.count) bytes"
                )

            // Claim the (possibly half-open) probe slot right before the upload, so a
            // recovering backend is exercised by exactly one artifact.
            guard await circuitBreaker.shouldAttempt() else {
                Logger.current.debug("CAS.save skipping upload (circuit open) for fingerprint: \(fingerprint)")
                response.casID = message
                response.contents = .casID(message)
                return response
            }

            do {
                let cacheURL = try await cacheURLStore.getCacheURL(for: serverURL, accountHandle: accountHandle)
                let uploadStart = ProcessInfo.processInfo.systemUptime
                try await saveCacheCASService.saveCacheCAS(
                    compressedData,
                    casId: fingerprint,
                    fullHandle: fullHandle,
                    serverURL: cacheURL,
                    authenticationURL: serverURL,
                    serverAuthenticationController: serverAuthenticationController
                )
                let transferDuration = ProcessInfo.processInfo.systemUptime - uploadStart
                await circuitBreaker.recordSuccess()
                response.casID = message
                response.contents = .casID(message)

                let duration = ProcessInfo.processInfo.systemUptime - startTime

                storeMetadata(
                    size: data.count,
                    compressedSize: compressedData.count,
                    duration: duration * 1000,
                    transferDuration: transferDuration * 1000,
                    codecDuration: codecDuration * 1000,
                    for: fingerprint
                )
                Logger.current
                    .debug(
                        "CAS.save completed successfully in \(String(format: "%.3f", duration))s for fingerprint: \(fingerprint)"
                    )
            } catch {
                if casErrorIsBackendHealthy(error) {
                    await circuitBreaker.recordSuccess()
                } else {
                    await circuitBreaker.recordFailure()
                }
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
            transferDuration: TimeInterval,
            codecDuration: TimeInterval,
            for casID: String
        ) {
            Task {
                do {
                    try analyticsDatabase.storeCASOutput(
                        key: casID,
                        size: size,
                        duration: duration,
                        compressedSize: compressedSize,
                        transferDuration: transferDuration,
                        codecDuration: codecDuration
                    )
                } catch {
                    Logger.current.error(
                        "Failed to store CAS metadata for casID: \(casID): \(error)"
                    )
                }
            }
        }
    }

#endif
