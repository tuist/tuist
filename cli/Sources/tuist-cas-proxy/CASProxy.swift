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
    private let putCASValueService: PutCASValueServicing
    
    init(config: TuistCore.Tuist, putCASValueService: PutCASValueServicing = PutCASValueService()) {
        self.config = config
        self.putCASValueService = putCASValueService
    }
    
    func putValue(request: CompilationCacheService_Keyvalue_V1_PutValueRequest, context: ServerContext) async throws -> CompilationCacheService_Keyvalue_V1_PutValueResponse {
        print(try request.jsonString())
        let binaryKey = request.key.dropFirst()
        let casID = "0~" + binaryKey.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        print("  Put value entries \(casID)", request.value.entries)
        print("  Put value entry values \(casID)", request.value.entries.values.map { $0.base64EncodedString() })
        print("  Put value cache key: \(casID)")
        
        let serverURL = config.url
        guard let fullHandle = config.fullHandle else { 
            print("❌ Error: No fullHandle configured")
            return CompilationCacheService_Keyvalue_V1_PutValueResponse()
        }
        
        // Convert protobuf entries to [String: String] format
        var entries: [String: String] = [:]
        for (key, data) in request.value.entries {
            entries[key] = data.base64EncodedString()
        }
        
        do {
            try await putCASValueService.putCASValue(
                casId: casID,
                entries: entries,
                fullHandle: fullHandle,
                serverURL: serverURL
            )
            print("✅ Successfully stored CAS value entries for \(casID)")
        } catch {
            print("❌ Error storing CAS value: \(error)")
        }
        
        return CompilationCacheService_Keyvalue_V1_PutValueResponse()
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
        
        var response = CompilationCacheService_Keyvalue_V1_GetValueResponse()
//        if casID == "0~mWDwdKKyuOJZbYfa7J6KbMT59jffSpsk9Ygaunmq5fKO6ZgvS7LkqbKYwq-lr46c8HcvaTF7c9zId4pmX2eXyQ==" {
//            var value = CompilationCacheService_Keyvalue_V1_Value()
//            value.entries = [
//                "value":  Data(
//                    base64Encoded: "CgQKAgABEqIBEp8BCkEADer7hRmI4NTCmYu2Jm1tPaKDj/NnMhh4RRjYMooOonMKumX1S9VKTT49tyVDqOzHPtMQFoT6oAqDUFuHoWyaNxJaMH44RS1NMk5jSmJ6Rk9FOHRGOUw0OWwtVHJud0FiMVFVXzNLMm45U1E0NXpEcXBETGVPTXVLeGlPLU1MV0dCSXlzYWRJMVM2R2g3Yll5RDE0Z1VDcVJLUT09EgIKABIrCilsbHZtOjpjYXM6OnNjaGVtYTo6Y29tcGlsZV9qb2JfcmVzdWx0Ojp2MQ=="
//                )!
//            ]
//            response.contents = .value(value)
//            response.outcome = .success
//            return response
//        }
        
        
        // For now, always return cache miss
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
        print(try request.jsonString())
        let casID = String(data: request.casID.id, encoding: .utf8)!
        print("Load value cas ID: \(casID)")
        var response = CompilationCacheService_Cas_V1_CASLoadResponse()
        fatalError()
    }
    
    func put(request: CompilationCacheService_Cas_V1_CASPutRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASPutResponse {
        fatalError()
    }
    
    func get(request: CompilationCacheService_Cas_V1_CASGetRequest, context: GRPCCore.ServerContext) async throws -> CompilationCacheService_Cas_V1_CASGetResponse {
        fatalError()
    }
    
    private let config: TuistCore.Tuist
    private let uploadCASArtifactService: UploadCASArtifactServicing
    
    init(config: TuistCore.Tuist, uploadCASArtifactService: UploadCASArtifactServicing = UploadCASArtifactService()) {
        self.config = config
        self.uploadCASArtifactService = uploadCASArtifactService
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
