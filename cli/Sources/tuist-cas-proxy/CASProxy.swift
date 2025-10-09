import ArgumentParser
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
                FallbackCASProxyService(),
                try ReflectionService(descriptorSetFileURLs: []),
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
            let base64Key = binaryKey.base64EncodedString()
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

@available(macOS 15.0, *)
struct FallbackCASProxyService: RegistrableRPCService {
    private let keyValueService = CASProxyService()

    func registerMethods(with router: inout RPCRouter<some ServerTransport>) {
        print("🔧 Registering fallback handlers for alternate service paths...")

        // Register handlers for alternate paths that Xcode might use
        let alternatePaths = [
            MethodDescriptor(fullyQualifiedService: "", method: "builtin-swiftCachingKeyQuery"),
            MethodDescriptor(fullyQualifiedService: "builtin-swiftCachingKeyQuery", method: "Query"),
        ]

        for method in alternatePaths {
            print("  Registering alternate path: '\(method.service)/\(method.method)'")

            router.registerHandler(
                forMethod: method,
                deserializer: GRPCProtobuf.ProtobufDeserializer<CompilationCacheService_Keyvalue_V1_GetValueRequest>(),
                serializer: GRPCProtobuf.ProtobufSerializer<CompilationCacheService_Keyvalue_V1_GetValueResponse>()
            ) { streamRequest, context in
                print("✅ Alternate handler triggered for: '\(method.service)/\(method.method)'")
                let singleRequest = try await ServerRequest(stream: streamRequest)
                let response = try await keyValueService.getValue(
                    request: singleRequest.message,
                    context: context
                )
                return StreamingServerResponse(single: ServerResponse(message: response, metadata: [:]))
            }
        }

        print("🔧 Fallback handler registration complete!")
    }
}

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
        print("  CAS ID: \(request.casID.base64EncodedString())")
        print("  Data size: \(request.data.count) bytes")
        print("  Type: \(request.type)")
        print("  Metadata: \(request.metadata)")

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

            // Convert CAS ID to string format expected by server (version~hash)
            let casIdString = "0~\(request.casID.base64EncodedString())"

            print("  Server URL: \(serverURL)")
            print("  Full Handle: \(fullHandle)")
            print("  CAS ID String: \(casIdString)")

            if !request.data.isEmpty {
                // Upload the artifact
                try await uploadService.uploadCASArtifact(
                    request.data,
                    casId: casIdString,
                    fullHandle: fullHandle,
                    serverURL: serverURL
                )
            } else {
                print("Data is empty")
            }

            print("✅ CAS artifact uploaded successfully")

            var response = CompilationCacheService_Cas_V1_SaveResponse()
            response.casID = request.casID
            response.success = true
            response.message = "Artifact uploaded successfully"
            return response

        } catch {
            print("❌ Error uploading CAS artifact: \(error)")

            var response = CompilationCacheService_Cas_V1_SaveResponse()
            response.casID = request.casID
            response.success = false
            response.message = "Upload failed: \(error.localizedDescription)"
            return response
        }
    }
}
