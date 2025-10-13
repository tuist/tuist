import ArgumentParser
import CommonCrypto
import CryptoKit
@preconcurrency import FileSystem
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import GRPCReflectionService
import Path
import SwiftProtobuf
@preconcurrency import TuistCore
@preconcurrency import TuistLoader
@preconcurrency import TuistServer

@available(macOS 15.0, *)
@main
struct CASProxy: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "CAS Proxy server for Xcode Compilation Cache"
    )
    
    @Argument(help: "Unix domain socket path")
    var socketPath: String = "cas.sock"
    
    func run() async throws {
        print("Starting CAS Proxy server...")
        
        // Load config once at startup
        let configLoader = ConfigLoader()
        let currentPath = try AbsolutePath(validating: "/Users/marekfort/Developer/tuist/cli/Fixtures/xcode_project_with_ios_app_and_cas")
        let config = try await configLoader.loadConfig(path: currentPath)
        
        // Remove existing socket if it exists
        try? FileManager.default.removeItem(atPath: socketPath)
        
        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .unixDomainSocket(path: socketPath),
                transportSecurity: .plaintext
            ),
            services: [
                KeyValueService(config: config),
                CASDBServiceImpl(config: config),
            ]
        )
        
        try await withThrowingDiscardingTaskGroup { group in
            group.addTask {
                print("🚀 Starting server.serve()...")
                try await server.serve()
            }
            
            // Print server info when ready
            if let address = try await server.listeningAddress {
                print("✅ CAS Proxy listening on \(address)")
                print(socketPath)
                print("📂 Socket file exists: \(FileManager.default.fileExists(atPath: socketPath))")
            }
            
            // Add a small delay to ensure server is ready
            try await Task.sleep(for: .milliseconds(100))
            print("📡 Server is ready to accept connections!")
        }
    }
}

// MARK: - CAS Proxy Service Implementation

@available(macOS 15.0, *)
struct KeyValueService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol {
    private let config: TuistCore.Tuist
    private let putKeyValueService: PutKeyValueServicing
    private let getKeyValueService: GetKeyValueServicing
    
    init(config: TuistCore.Tuist, putKeyValueService: PutKeyValueServicing = PutKeyValueService(), getKeyValueService: GetKeyValueServicing = GetKeyValueService()) {
        self.config = config
        self.putKeyValueService = putKeyValueService
        self.getKeyValueService = getKeyValueService
    }
    
    func putValue(request: CompilationCacheService_Keyvalue_V1_PutValueRequest, context: ServerContext) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        print(try request.jsonString())
        let binaryKey = request.key.dropFirst()
        let casID = "0~" + binaryKey.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        
        let serverURL = config.url
        guard let fullHandle = config.fullHandle else { 
            return CompilationCacheService_Keyvalue_V1_PutValueResponse()
        }
        
        // Convert protobuf entries to [String: String] format
        var entries: [String: String] = [:]
        for (key, data) in request.value.entries {
            entries[key] = data.base64EncodedString()
        }
        
        var response = CompilationCacheService_Keyvalue_V1_PutValueResponse()
        do {
            try await putKeyValueService.putKeyValue(
                casId: casID,
                entries: entries,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            return response
        } catch let error {
            var responseError = CompilationCacheService_Keyvalue_V1_ResponseError()
            responseError.description_p = error.localizedDescription
            response.error = responseError
            return response
        }
        
        
    }
    
    func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        print("🔍 KeyValueDB.GetValue called")
        print("  Request message size: \(request.key.count) bytes")
        
        // Analyze the key data
        // This appears to be the format: 0x00 followed by 64 bytes of binary data
        let binaryKey = request.key.dropFirst()
        let casID = "0~" + binaryKey.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        print("  Cache key: \(casID)")
        
        let serverURL = config.url
        guard let fullHandle = config.fullHandle else { 
            var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
            response.outcome = .keyNotFound
            return response
        }
        
        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
        
        do {
            if let json = try await getKeyValueService.getKeyValue(
                casId: casID,
                fullHandle: fullHandle,
                serverURL: serverURL
            ) {
                // Convert the entries back to protobuf format
                var value = CompilationCacheService_Keyvalue_V1_Value()
                for entry in json.entries {
                    if let data = Data(base64Encoded: entry.value) {
                        value.entries["value"] = data
                    }
                }
                response.contents = .value(value)
                response.outcome = .success
                print("  Sending GetValue response: found=true (cache hit)")
            } else {
                response.outcome = .keyNotFound
                print("  Sending GetValue response: found=false (cache miss)")
            }
        } catch {
            print("  Error retrieving value: \(error.localizedDescription)")
            response.outcome = .keyNotFound
        }
        
        return response
    }
}

// MARK: - Fallback Service for compatibility

// MARK: - Extensions

extension Data {
    var hexString: String {
        return map { String(format: "%02x", $0) }.joined()
    }
}

extension Character {
    var isPrintable: Bool {
        return isASCII && (isLetter || isNumber || isPunctuation || isSymbol || isWhitespace)
    }
}

// MARK: - CAS Database Service Implementation

@available(macOS 15.0, *)
struct CASDBServiceImpl: CompilationCacheService_Cas_V1_CASDBService.SimpleServiceProtocol {
    func load(request: CompilationCacheService_Cas_V1_CASLoadRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASLoadResponse {
        print(try request.jsonString())
        let casID = String(data: request.casID.id, encoding: .utf8)!
        print("Load value cas ID: \(casID)")
        
        let serverURL = config.url
        let fullHandle = config.fullHandle!
        
        var response = CompilationCacheService_Cas_V1_CASLoadResponse()
        
        do {
            let data = try await loadCASService.loadCAS(
                casId: casID.hasPrefix("0~") ? String(casID.dropFirst(2)) : casID,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            
            var bytes = CompilationCacheService_Cas_V1_CASBytes()
            bytes.data = data

            // Create response with the loaded data
            var blob = CompilationCacheService_Cas_V1_CASBlob()
            blob.blob = bytes
            
            response.contents = .data(blob)
            response.outcome = .success
            
            print("  Successfully loaded CAS artifact: \(data.count) bytes")
            
        } catch let error {
            print("  Error loading CAS artifact: \(error.localizedDescription)")
            response.outcome = .error
            var responseError = CompilationCacheService_Cas_V1_ResponseError()
            responseError.description_p = error.localizedDescription
            response.contents = .error(responseError)
        }
        
        return response
    }
    
    func put(request: CompilationCacheService_Cas_V1_CASPutRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASPutResponse {
        fatalError()
    }
    
    func get(request: CompilationCacheService_Cas_V1_CASGetRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASGetResponse {
        fatalError()
    }
    
    private let config: TuistCore.Tuist
    private let uploadCASArtifactService: UploadCASArtifactServicing
    private let loadCASService: LoadCASServicing
    
    init(config: TuistCore.Tuist, uploadCASArtifactService: UploadCASArtifactServicing = UploadCASArtifactService(), loadCASService: LoadCASServicing = LoadCASService()) {
        self.config = config
        self.uploadCASArtifactService = uploadCASArtifactService
        self.loadCASService = loadCASService
    }

    
    func save(
        request: CompilationCacheService_Cas_V1_CASSaveRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASSaveResponse {
        let serverURL = config.url
        
        guard let fullHandle = config.fullHandle else { fatalError() }
        
        print("  Server URL: \(serverURL)")
        print("  Full Handle: \(fullHandle)")
        
        // Compute SHA-512 checksum of the data
        let data: Data
        if !request.data.blob.filePath.isEmpty {
            // Read data from file path
            let fileURL = URL(fileURLWithPath: request.data.blob.filePath)
            data = try Data(contentsOf: fileURL)
            print("  Reading data from file: \(request.data.blob.filePath)")
            print("  File size: \(data.count) bytes")
        } else {
            // Use the provided data
            data = request.data.blob.data
        }
        
        if data.isEmpty {
            fatalError()
        }
        
        let digest = SHA512.hash(data: data)
        let hashData = Data(digest)
        let casID = hashData.base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        
        try! await uploadCASArtifactService.uploadCASArtifact(
            data,
            casId: casID,
            fullHandle: fullHandle,
            serverURL: serverURL
        )
        
        
        var response = CompilationCacheService_Cas_V1_CASSaveResponse()
        var message = CompilationCacheService_Cas_V1_CASDataID()
        message.id = ("0~" + casID).data(using: String.Encoding.utf8)!
        response.casID = message
        return response
        
        //        } catch {
        //            print("❌ Error uploading CAS artifact: \(error)")
        //
        //            var response = CompilationCacheService_Cas_V1_SaveResponse()
        ////            response.casID = casIdToUse
        //            response.success = false
        //            response.message = "Upload failed: \(error.localizedDescription)"
        //            return response
        //        }
    }
}
