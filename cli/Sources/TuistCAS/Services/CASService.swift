import CryptoKit
@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Path
import TuistServer
import TuistSupport

public struct CASService: CompilationCacheService_Cas_V1_CASDBService.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let casWorkerURL: URL
    private let saveCacheCASService: SaveCacheCASServicing
    private let loadCacheCASService: LoadCacheCASServicing
    private let fileSystem: FileSysteming

    public init(
        fullHandle: String,
        serverURL: URL,
        casWorkerURL: URL? = nil,
        saveCacheCASService: SaveCacheCASServicing = SaveCacheCASService(),
        loadCacheCASService: LoadCacheCASServicing = LoadCacheCASService(),
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.casWorkerURL = casWorkerURL ?? serverURL
        self.saveCacheCASService = saveCacheCASService
        self.loadCacheCASService = loadCacheCASService
        self.fileSystem = fileSystem
    }

    private func cacheDirectory() async throws -> AbsolutePath {
        let cacheDir = Environment.current.stateDirectory.appending(component: "cache")
        if try await !fileSystem.exists(cacheDir) {
            try await fileSystem.makeDirectory(at: cacheDir)
        }
        return cacheDir
    }

    public func load(
        request: CompilationCacheService_Cas_V1_CASLoadRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASLoadResponse {
        var response = CompilationCacheService_Cas_V1_CASLoadResponse()

        guard let casID = String(data: request.casID.id, encoding: .utf8) else {
            response.outcome = .error
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = "Invalid CAS ID: Unable to decode CAS ID as UTF-8 string"
            response.error = responseError
            response.contents = .error(responseError)
            return response
        }

        do {
            // First check if the file exists in local cache
            let cacheDir = try await cacheDirectory()
            let localPath = cacheDir.appending(component: casID)

            let data: Data
            if try await fileSystem.exists(localPath) {
                // Load from local cache
                data = try await fileSystem.readFile(at: localPath)
            } else {
                // File not found locally, this shouldn't happen after get() extracts the zip
                response.outcome = .error
                var responseError = CompilationCacheService_Cas_V1_ResponseError()
                responseError.description_p = "CAS object not found in local cache: \(casID)"
                response.error = responseError
                response.contents = .error(responseError)
                return response
            }

            var bytes = CompilationCacheService_Cas_V1_CASBytes()
            bytes.data = data

            var blob = CompilationCacheService_Cas_V1_CASBlob()
            blob.blob = bytes

            response.contents = .data(blob)
            response.outcome = .success
        } catch {
            response.outcome = .error
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            response.error = responseError
            response.contents = .error(responseError)
        }

        return response
    }

    public func save(
        request: CompilationCacheService_Cas_V1_CASSaveRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASSaveResponse {
        var response = CompilationCacheService_Cas_V1_CASSaveResponse()

        let data: Data
        if !request.data.blob.filePath.isEmpty {
            do {
                let absolutePath = try AbsolutePath(validating: request.data.blob.filePath)
                data = try await fileSystem.readFile(at: absolutePath)
            } catch {
                var responseError = CompilationCacheService_Cas_V1_ResponseError()
                responseError.description_p = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                response.error = responseError
                response.contents = .error(responseError)
                return response
            }
        } else {
            data = request.data.blob.data
        }

        let hash = SHA256.hash(data: data)
        let fingerprint = hash.compactMap { String(format: "%02X", $0) }.joined()

        var message = CompilationCacheService_Cas_V1_CASDataID()
        message.id = fingerprint.data(using: .utf8)!
        print(message.id.base64EncodedString())

        do {
            // Store the file locally in the cache directory
            let cacheDir = try await cacheDirectory()
            let localPath = cacheDir.appending(component: fingerprint)

            if try await !fileSystem.exists(localPath) {
                try Data(data).write(to: localPath.url)
            }

            response.casID = message
            response.contents = .casID(message)
        } catch {
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            response.error = responseError
            response.contents = .error(responseError)
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
