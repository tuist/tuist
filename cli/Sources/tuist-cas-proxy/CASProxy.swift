import ArgumentParser
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCProtobuf
import GRPCReflectionService
import SwiftProtobuf

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
        
        // Remove existing socket if it exists
        try? FileManager.default.removeItem(atPath: socketPath)
        
        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .unixDomainSocket(path: socketPath),
                transportSecurity: .plaintext
            ),
            services: [
                CASProxyService(),
                FallbackCASProxyService(),
                try ReflectionService(descriptorSetFileURLs: [])
            ],
            interceptors: [
                DebugInterceptor()
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
struct CASProxyService: Cas_KeyValueDB.SimpleServiceProtocol {
    func getValue(
        request: Cas_GetValueRequest,
        context: GRPCCore.ServerContext
    ) async throws -> Cas_GetValueResponse {
        print("🔍 KeyValueDB.GetValue called")
        print("  Request message size: \(request.key.count) bytes")
        
        // Analyze the key data
        if request.key.isEmpty {
            print("  Empty key received")
        } else if request.key.count == 65 && request.key[0] == 0x00 {
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
        var response = Cas_GetValueResponse()
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
    
    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        print("🔧 Registering fallback handlers for alternate service paths...")
        
        // Register handlers for alternate paths that Xcode might use
        let alternatePaths = [
            MethodDescriptor(fullyQualifiedService: "compilation_cache_service.keyvalue.v1.KeyValueDB", method: "GetValue"),
            MethodDescriptor(fullyQualifiedService: "", method: "builtin-swiftCachingKeyQuery"),
            MethodDescriptor(fullyQualifiedService: "builtin-swiftCachingKeyQuery", method: "Query"),
        ]
        
        for method in alternatePaths {
            print("  Registering alternate path: '\(method.service)/\(method.method)'")
            
            router.registerHandler(
                forMethod: method,
                deserializer: GRPCProtobuf.ProtobufDeserializer<Cas_GetValueRequest>(),
                serializer: GRPCProtobuf.ProtobufSerializer<Cas_GetValueResponse>()
            ) { streamRequest, context in
                print("✅ Alternate handler triggered for: '\(method.service)/\(method.method)'")
                let singleRequest = try await ServerRequest(stream: streamRequest)
                let response = try await self.keyValueService.getValue(
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
