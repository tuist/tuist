@preconcurrency import FileSystem
import Foundation
import GRPCCore
import Path
import TuistServer
import TuistSupport
import ZIPFoundation

// MARK: - CAS Cache Value Structure

struct CASCacheValue: Codable {
    let cas_id: String
    let entries: [Entry]
    
    struct Entry: Codable {
        let key: String
        let value: String // checksum
    }
}

public struct KeyValueService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol {
    private let fullHandle: String
    private let serverURL: URL
    private let casWorkerURL: URL
    private let putCacheValueService: PutCacheValueServicing
    private let getCacheValueService: GetCacheValueServicing
    private let fileSystem: FileSysteming
    private let saveCacheCASService: SaveCacheCASServicing
    private let loadCacheCASService: LoadCacheCASServicing

    public init(
        fullHandle: String,
        serverURL: URL,
        casWorkerURL: URL? = nil,
        putCacheValueService: PutCacheValueServicing = PutCacheValueService(),
        getCacheValueService: GetCacheValueServicing = GetCacheValueService(),
        fileSystem: FileSysteming = FileSystem(),
        saveCacheCASService: SaveCacheCASServicing = SaveCacheCASService(),
        loadCacheCASService: LoadCacheCASServicing = LoadCacheCASService()
    ) {
        self.fullHandle = fullHandle
        self.serverURL = serverURL
        self.casWorkerURL = casWorkerURL ?? serverURL
        self.putCacheValueService = putCacheValueService
        self.getCacheValueService = getCacheValueService
        self.fileSystem = fileSystem
        self.saveCacheCASService = saveCacheCASService
        self.loadCacheCASService = loadCacheCASService
    }

    private func cacheDirectory() throws -> AbsolutePath {
        let cacheDir = Environment.shared.stateDirectory.appending(component: "cache")
        if !fileSystem.exists(cacheDir) {
            try fileSystem.makeDirectory(at: cacheDir)
        }
        return cacheDir
    }

    public func putValue(
        request: CompilationCacheService_Keyvalue_V1_PutValueRequest,
        context _: ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        let casID = converKeyToCasID(request.key)

        var response = CompilationCacheService_Keyvalue_V1_PutValueResponse()
        do {
            // Create temporary directory for zip contents
            let tempDir = try TemporaryDirectory()
            let tempPath = try AbsolutePath(validating: tempDir.path.path)
            
            // Convert entries to proper format and collect checksums
            var entriesForJSON: [String: String] = [:]
            
            // Copy all files from cache directory to temp directory based on entries
            let cacheDir = try cacheDirectory()
            for (key, data) in request.value.entries {
                if let checksum = String(data: data, encoding: .utf8) {
                    entriesForJSON[key] = checksum
                    
                    // Copy file from cache to temp directory
                    let sourcePath = cacheDir.appending(component: checksum)
                    let destPath = tempPath.appending(component: checksum)
                    
                    if fileSystem.exists(sourcePath) {
                        try await fileSystem.copy(from: sourcePath, to: destPath)
                    }
                }
            }
            
            // Create cas.json
            let casJSON = CASCacheValue(cas_id: casID, entries: entriesForJSON.map { CASCacheValue.Entry(key: $0.key, value: $0.value) })
            let jsonData = try JSONEncoder().encode(casJSON)
            let jsonPath = tempPath.appending(component: "cas.json")
            try await fileSystem.write(jsonPath, contents: jsonData)
            
            // Create zip file
            let zipPath = tempPath.appending(component: "\(casID).zip")
            let zipURL = zipPath.url
            let tempURL = tempPath.url
            
            try FileManager.default.zipItem(at: tempURL, to: zipURL, shouldKeepParent: false)
            
            // Upload the zip file
            let zipData = try Data(contentsOf: zipURL)
            try await saveCacheCASService.saveCacheCAS(
                zipData,
                casId: casID,
                fullHandle: fullHandle,
                casWorkerURL: casWorkerURL
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
            // Download the zip file using loadCacheCAS
            let zipData = try await loadCacheCASService.loadCacheCAS(
                casId: casID,
                fullHandle: fullHandle,
                casWorkerURL: casWorkerURL
            )
            
            // Create temporary directory for extraction
            let tempDir = try TemporaryDirectory()
            let tempPath = try AbsolutePath(validating: tempDir.path.path)
            
            // Write zip to temp file
            let zipPath = tempPath.appending(component: "\(casID).zip")
            try await fileSystem.write(zipPath, contents: zipData)
            
            // Extract zip
            try FileManager.default.unzipItem(at: zipPath.url, to: tempPath.url)
            
            // Read cas.json
            let jsonPath = tempPath.appending(component: "cas.json")
            let jsonData = try await fileSystem.readFile(at: jsonPath)
            let casValue = try JSONDecoder().decode(CASCacheValue.self, from: jsonData)
            
            // Move extracted files to cache directory
            let cacheDir = try cacheDirectory()
            for entry in casValue.entries {
                let sourcePath = tempPath.appending(component: entry.value)
                let destPath = cacheDir.appending(component: entry.value)
                
                if fileSystem.exists(sourcePath) && !fileSystem.exists(destPath) {
                    try await fileSystem.copy(from: sourcePath, to: destPath)
                }
            }
            
            // Create response with the entries
            var value = CompilationCacheService_Keyvalue_V1_Value()
            for entry in casValue.entries {
                value.entries[entry.key] = entry.value.data(using: .utf8) ?? Data()
            }
            response.contents = .value(value)
            response.outcome = .success
            
        } catch {
            // Check if it's a not found error
            if (error as? LoadCacheCASServiceError) != nil {
                response.outcome = .keyNotFound
            } else {
                var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
                responseError.description_p = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                response.error = responseError
                response.outcome = .keyNotFound
            }
        }

        return response
    }

    private func converKeyToCasID(_ key: Data) -> String {
        "0~" + key.dropFirst().base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
    }
}
