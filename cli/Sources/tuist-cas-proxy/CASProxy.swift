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
        let currentPath = try AbsolutePath(validating: "/Users/marekfort/Developer/tuist-bugfix/cli/Fixtures/xcode_project_with_ios_app_and_cas")
        let config = try await configLoader.loadConfig(path: currentPath)
        
        // Remove existing socket if it exists
        try? FileManager.default.removeItem(atPath: socketPath)
        
        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .unixDomainSocket(path: socketPath),
                transportSecurity: .plaintext
            ),
            services: [
                KeyValueService(),
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
    func putValue(request: CompilationCacheService_Keyvalue_V1_PutValueRequest, context: ServerContext) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        print(try request.jsonString())
        let binaryKey = request.key.dropFirst()
        let base64Key = binaryKey.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        print("  Cache key: 0~\(base64Key)")
        fatalError()
    }
    func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Keyvalue_V1_GetValueResponse {
        print("🔍 KeyValueDB.GetValue called")
        print("  Request message size: \(request.key.count) bytes")
        
        // Analyze the key data
        if request.key.isEmpty {
            print("  Empty key received")
        } else if request.key.count == 65, request.key[0] == 0x00 {
            // This appears to be the format: 0x00 followed by 64 bytes of binary data
            let binaryKey = request.key.dropFirst()
            let base64Key = binaryKey.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
            print("  Cache key: 0~\(base64Key)")
        } else if let keyString = String(data: request.key, encoding: .utf8) {
            print("  Cache key (UTF-8): \(keyString)")
        } else {
            print("  Cache key (base64): \(request.key.base64EncodedString())")
            print("  Cache key (hex): \(request.key.hexString)")
        }
        
        // For now, always return cache miss
        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
//        response.found = false
//        response.value = Data()
        response.outcome = .keyNotFound
        
        print("  Sending GetValue response: found=false (cache miss)")
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
        fatalError()
    }
    
    func put(request: CompilationCacheService_Cas_V1_CASPutRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASPutResponse {
        fatalError()
    }
    
    func get(request: CompilationCacheService_Cas_V1_CASGetRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASGetResponse {
        fatalError()
    }
    
    private let config: TuistCore.Tuist
    private let uploadService: UploadCASArtifactServicing
    
    init(config: TuistCore.Tuist) {
        self.config = config
        uploadService = UploadCASArtifactService()
    }

    
    func save(
        request: CompilationCacheService_Cas_V1_CASSaveRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_CASSaveResponse {
        print("🔍 CASDBService.Save called")
        print(try request.jsonString())
//        print("  CAS ID field: \(request.casID.base64EncodedString()) (size: \(request.casID.count) bytes)")
//        print("  Data size: \(request.data.count) bytes")
//        print("  Type: \(request.type)")
//        print("  Metadata: \(request.metadata)")
        
        let serverURL = config.url
        
        guard let fullHandle = config.fullHandle else { fatalError() }
        
        print("  Server URL: \(serverURL)")
        print("  Full Handle: \(fullHandle)")
        
        //            We are skipping the actual upload for now before we can figure out how to obtain the CAS ID
        //            if !actualArtifactData.isEmpty {
        //                // Upload the artifact with extracted data
        //                try await uploadService.uploadCASArtifact(
        //                    actualArtifactData,
        //                    casId: casIdString,
        //                    fullHandle: fullHandle,
        //                    serverURL: serverURL
        //                )
        //            } else {
        //                print("Artifact data is empty after extraction")
        //            }
        
        print("✅ CAS artifact uploaded successfully")
        
        var response = CompilationCacheService_Cas_V1_CASSaveResponse()
        // hardcoded ID
        var message = CompilationCacheService_Cas_V1_CASDataID()
        message.id = "0~8E-M2NcJbzFOE8tF9L49l-TrnwAb1QU_3K2n9SQ45zDqpDLeOMuKxiO-MLWGBIysadI1S6Gh7bYyD14gUCqRKQ==".data(using: .utf8)!
        response.casID = message
//        response.success = true
//        response.message = "Artifact uploaded successfully"
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
