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
                CASProxyService(),
                CASDBServiceImpl(config: config),
            ],
            interceptors: [
                DebugInterceptor(),
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

// MARK: - Debug Interceptor

@available(macOS 15.0, *)
struct DebugInterceptor: ServerInterceptor {
    func intercept<Input: Sendable, Output: Sendable>(
        request: StreamingServerRequest<Input>,
        context: ServerContext,
        next: @Sendable (StreamingServerRequest<Input>, ServerContext) async throws -> StreamingServerResponse<Output>
    ) async throws -> StreamingServerResponse<Output> {
        print("🔍 INTERCEPTED REQUEST:")
        print("  Method: \(context.descriptor.fullyQualifiedMethod)")
        print("  Metadata: \(request.metadata)")
        print("  Input type: \(Input.self)")
        print("  Output type: \(Output.self)")

        do {
            let response = try await next(request, context)
            print("✅ Request completed successfully")
            return response
        } catch {
            print("❌ Request failed: \(error)")
            throw error
        }
    }
}

// MARK: - CAS Proxy Service Implementation

@available(macOS 15.0, *)
struct CASProxyService: CompilationCacheService_Keyvalue_V1_KeyValueDB.SimpleServiceProtocol {
    func getValue(
        request: CompilationCacheService_Keyvalue_V1_GetValueRequest,
        context _: GRPCCore.ServerContext
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
        response.found = false
        response.value = Data()

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
    private let config: TuistCore.Tuist
    private let uploadService: UploadCASArtifactServicing

    init(config: TuistCore.Tuist) {
        self.config = config
        uploadService = UploadCASArtifactService()
    }

    func save(
        request: CompilationCacheService_Cas_V1_SaveRequest,
        context _: GRPCCore.ServerContext
    ) async throws -> CompilationCacheService_Cas_V1_SaveResponse {
        print("🔍 CASDBService.Save called")
        print("  CAS ID field: \(request.casID.base64EncodedString()) (size: \(request.casID.count) bytes)")
        print("  Data size: \(request.data.count) bytes")
        print("  Type: \(request.type)")
        print("  Metadata: \(request.metadata)")
        
        // Print raw data for analysis
        print("📊 RAW DATA ANALYSIS:")
        print("  First 200 bytes (hex): \(request.data.prefix(200).hexString)")
        print("  First 200 bytes (base64): \(request.data.prefix(200).base64EncodedString())")
        
        // Try to find patterns in the data
        if request.data.count >= 100 {
            print("  Bytes 0-32 (hex): \(request.data.prefix(32).hexString)")
            print("  Bytes 0-64 (hex): \(request.data.prefix(64).hexString)")
            print("  Bytes 32-64 (hex): \(request.data.dropFirst(32).prefix(32).hexString)")
            print("  Bytes 64-96 (hex): \(request.data.dropFirst(64).prefix(32).hexString)")
        }
        
        // Parse protobuf structure to extract the artifact data and compute CAS ID
        var extractedCasId: Data = Data()
        var actualArtifactData: Data = request.data
        
        // Try to decode protobuf varint encoding
        func decodeProtobufField(from data: Data, startIndex: Int) -> (fieldNumber: Int, wireType: Int, valueData: Data, nextIndex: Int)? {
            guard startIndex < data.count else { return nil }
            
            // Decode varint tag
            var index = startIndex
            var tag: UInt64 = 0
            var shift = 0
            
            while index < data.count {
                let byte = data[index]
                tag |= UInt64(byte & 0x7F) << shift
                index += 1
                if (byte & 0x80) == 0 { break }
                shift += 7
                if shift >= 64 { return nil }
            }
            
            let fieldNumber = Int(tag >> 3)
            let wireType = Int(tag & 0x7)
            
            print("    Protobuf field: #\(fieldNumber), wireType: \(wireType)")
            
            // Handle wire type 2 (length-delimited)
            if wireType == 2 {
                // Decode length varint
                var length: UInt64 = 0
                shift = 0
                
                while index < data.count {
                    let byte = data[index]
                    length |= UInt64(byte & 0x7F) << shift
                    index += 1
                    if (byte & 0x80) == 0 { break }
                    shift += 7
                    if shift >= 64 { return nil }
                }
                
                let dataLength = Int(length)
                guard index + dataLength <= data.count else { return nil }
                
                let valueData = Data(data[index..<index + dataLength])
                
                return (fieldNumber, wireType, valueData, index + dataLength)
            }
            
            return nil
        }
        
        // Parse the protobuf structure to extract field 1 (artifact data)
        print("🔍 PROTOBUF PARSING:")
        if let field = decodeProtobufField(from: request.data, startIndex: 0) {
            print("  Field \(field.fieldNumber): \(field.valueData.count) bytes")
            
            if field.fieldNumber == 1 {
                // Field 1 contains the actual artifact data
                actualArtifactData = field.valueData
                print("  ✅ Extracted artifact data from field 1")
                
                // Try different hashing approaches to match expected CAS ID
                print("  🔍 Trying different hash algorithms:")
                
                // SHA-256 of artifact data
                let sha256Hash = SHA256.hash(data: actualArtifactData)
                let sha256Data = Data(sha256Hash)
                print("    SHA-256: \(sha256Data.base64EncodedString())")
                
                // SHA-512 of artifact data  
                let sha512Hash = SHA512.hash(data: actualArtifactData)
                let sha512Data = Data(sha512Hash)
                print("    SHA-512: \(sha512Data.base64EncodedString())")
                
                // Try hashing the original protobuf data (including field headers)
                let sha256OriginalHash = SHA256.hash(data: request.data)
                let sha256OriginalData = Data(sha256OriginalHash)
                print("    SHA-256 of original data: \(sha256OriginalData.base64EncodedString())")
                
                // Try SHA-512 of original data
                let sha512OriginalHash = SHA512.hash(data: request.data)
                let sha512OriginalData = Data(sha512OriginalHash)
                print("    SHA-512 of original data: \(sha512OriginalData.base64EncodedString())")
                
                // Try MD5 (less likely but possible)
                var md5Context = CC_MD5_CTX()
                CC_MD5_Init(&md5Context)
                actualArtifactData.withUnsafeBytes { bytes in
                    CC_MD5_Update(&md5Context, bytes.baseAddress, CC_LONG(bytes.count))
                }
                var md5Digest = Data(count: Int(CC_MD5_DIGEST_LENGTH))
                md5Digest.withUnsafeMutableBytes { bytes in
                    CC_MD5_Final(bytes.bindMemory(to: UInt8.self).baseAddress, &md5Context)
                }
                print("    MD5: \(md5Digest.base64EncodedString())")
                
                // Use SHA-256 as default for now
                extractedCasId = sha256Data
                
                print("  ✅ Using SHA-256 hash as CAS ID: \(extractedCasId.base64EncodedString())")
                print("  🎯 Expected CAS ID: eVk1nxQ7tmN1to73gnsc7pFYvIDv-czrh5mRytSNSj_XueKGssIOPHr8JwuHY4j-etpUKLuUWCzgcieaQOgtig==")
            }
        }
        
        print("  ✅ Final computed CAS ID: \(extractedCasId.base64EncodedString()) (size: \(extractedCasId.count) bytes)")
        print("  ✅ Final artifact data size: \(actualArtifactData.count) bytes")
        
        // Additional analysis patterns
        print("🔍 PATTERN ANALYSIS:")
        if request.data.count >= 4 {
            let first4 = request.data.prefix(4)
            print("  First 4 bytes (potential length): \(first4.hexString) = \(first4.withUnsafeBytes { $0.bindMemory(to: UInt32.self).first ?? 0 })")
            print("  First 4 bytes (little endian): \(UInt32(littleEndian: first4.withUnsafeBytes { $0.bindMemory(to: UInt32.self).first ?? 0 }))")
            print("  First 4 bytes (big endian): \(UInt32(bigEndian: first4.withUnsafeBytes { $0.bindMemory(to: UInt32.self).first ?? 0 }))")
        }
        
        // Look for null terminators or other separators
        if let nullIndex = request.data.firstIndex(of: 0) {
            print("  First null byte at index: \(nullIndex)")
            if nullIndex > 0 {
                let beforeNull = Data(request.data.prefix(nullIndex))
                print("  Data before null (hex): \(beforeNull.hexString)")
                print("  Data before null (base64): \(beforeNull.base64EncodedString())")
                if let stringBeforeNull = String(data: beforeNull, encoding: .utf8) {
                    print("  Data before null (UTF-8): \(stringBeforeNull)")
                }
            }
        }

        do {
            // Use pre-loaded config
            let serverURL = config.url
            if serverURL.absoluteString.isEmpty {
                print("❌ No server URL configured")
                var response = CompilationCacheService_Cas_V1_SaveResponse()
                response.casID = request.casID
                response.success = false
                response.message = "No server URL configured"
                return response
            }

            guard let fullHandle = config.fullHandle else {
                print("❌ No fullHandle configured")
                var response = CompilationCacheService_Cas_V1_SaveResponse()
                response.casID = request.casID
                response.success = false
                response.message = "No fullHandle configured. Run 'tuist init' to set up remote features."
                return response
            }

            // Convert extracted CAS ID to string format expected by server (version~hash)
            let casIdToUse = extractedCasId.isEmpty ? request.casID : extractedCasId
            let casIdString = "0~\(casIdToUse.base64EncodedString())"

            print("  Server URL: \(serverURL)")
            print("  Full Handle: \(fullHandle)")
            print("  CAS ID non-encoded: \(String(data: casIdToUse, encoding: .utf8))")
            print("  CAS ID String: \(casIdString)")

            if !actualArtifactData.isEmpty {
                // Upload the artifact with extracted data
                try await uploadService.uploadCASArtifact(
                    actualArtifactData,
                    casId: casIdString,
                    fullHandle: fullHandle,
                    serverURL: serverURL
                )
            } else {
                print("Artifact data is empty after extraction")
            }

            print("✅ CAS artifact uploaded successfully")

            var response = CompilationCacheService_Cas_V1_SaveResponse()
            response.casID = casIdToUse
            response.success = true
            response.message = "Artifact uploaded successfully"
            return response

        } catch {
            print("❌ Error uploading CAS artifact: \(error)")

            var response = CompilationCacheService_Cas_V1_SaveResponse()
//            response.casID = casIdToUse
            response.success = false
            response.message = "Upload failed: \(error.localizedDescription)"
            return response
        }
    }
}
