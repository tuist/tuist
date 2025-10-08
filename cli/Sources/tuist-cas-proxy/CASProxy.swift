import ArgumentParser
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import GRPCReflectionService

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

// MARK: - Protobuf Message Types

@available(macOS 15.0, *)
struct GetValueRequest {
    let key: String
    
    init(key: String) {
        self.key = key
    }
    
    static func decode(from data: Data) throws -> GetValueRequest {
        var index = 0
        var keyData = Data()
        
        while index < data.count {
            guard index < data.count else { break }
            
            let tag = data[index]
            index += 1
            
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            
            print("    Decoding field \(fieldNumber) with wire type \(wireType) at index \(index-1)")
            
            switch fieldNumber {
            case 1: // key field
                if wireType == 2 { // length-delimited
                    let (length, lengthEndIndex) = readVarint(data, from: index)
                    index = lengthEndIndex
                    
                    print("    Key field length: \(length)")
                    
                    if index + Int(length) <= data.count {
                        keyData = data[index..<index + Int(length)]
                        index += Int(length)
                        
                        // The key data might be nested protobuf, let's analyze it
                        print("    Key raw data: \(keyData.hexString)")
                        
                        // Check if this is nested protobuf (starts with field tag)
                        if !keyData.isEmpty {
                            let firstByte = keyData[keyData.startIndex]
                            let nestedFieldNumber = firstByte >> 3
                            let nestedWireType = firstByte & 0x07
                            print("    First byte: 0x\(String(format: "%02x", firstByte)), field \(nestedFieldNumber), wire type \(nestedWireType)")
                            
                            // Field 0 with wire type 0 is likely binary data, not nested protobuf
                            if firstByte == 0x00 && keyData.count >= 65 {
                                // This is binary data starting with 0x00
                                // Skip the first 0x00 byte and convert the rest to base64
                                let binaryData = keyData.dropFirst()
                                let base64Key = binaryData.base64EncodedString()
                                print("    Binary key (64 bytes) converted to base64: \(base64Key)")
                                return GetValueRequest(key: "0~" + base64Key)
                            }
                            
                            // Try to extract string from nested protobuf
                            if nestedWireType == 2 && keyData.count > 1 { // length-delimited
                                var nestedIndex = 1
                                if nestedIndex < keyData.count {
                                    let (nestedLength, nestedLengthEnd) = readVarint(keyData, from: nestedIndex)
                                    nestedIndex = nestedLengthEnd
                                    
                                    if nestedIndex >= 0 && nestedIndex + Int(nestedLength) <= keyData.count {
                                        let actualKeyData = keyData[nestedIndex..<nestedIndex + Int(nestedLength)]
                                        if let keyStr = String(data: actualKeyData, encoding: .utf8) {
                                            print("    Extracted nested key string: \(keyStr)")
                                            return GetValueRequest(key: keyStr)
                                        }
                                    }
                                }
                            }
                        }
                        
                        // Fallback: try direct UTF-8 decode
                        if let keyStr = String(data: keyData, encoding: .utf8) {
                            print("    Direct UTF-8 key: \(keyStr)")
                            return GetValueRequest(key: keyStr)
                        }
                        
                        // Last resort: convert binary to base64
                        let base64Key = keyData.base64EncodedString()
                        print("    Binary key as base64: \(base64Key)")
                        return GetValueRequest(key: base64Key)
                    }
                }
            default:
                // Skip unknown fields based on wire type
                switch wireType {
                case 0: // varint
                    let (_, newIndex) = readVarint(data, from: index)
                    index = newIndex
                case 1: // 64-bit
                    index += 8
                case 2: // length-delimited
                    let (length, lengthEndIndex) = readVarint(data, from: index)
                    index = lengthEndIndex + Int(length)
                case 5: // 32-bit
                    index += 4
                default:
                    break
                }
            }
        }
        
        // Return empty string if we couldn't decode
        return GetValueRequest(key: "")
    }
}

@available(macOS 15.0, *)
struct GetValueResponse {
    let found: Bool
    let value: Data
    
    init(found: Bool, value: Data = Data()) {
        self.found = found
        self.value = value
    }
    
    func encode() -> Data {
        var data = Data()
        
        // Field 1: found (bool)
        data.append(0x08) // tag = (1 << 3) | 0, wire type 0 (varint)
        data.append(found ? 0x01 : 0x00)
        
        // Field 2: value (bytes) - only if found
        if found && !value.isEmpty {
            data.append(0x12) // tag = (2 << 3) | 2, wire type 2 (length-delimited)
            data.append(contentsOf: encodeVarint(UInt64(value.count)))
            data.append(contentsOf: value)
        }
        
        return data
    }
}

// MARK: - CAS Proxy Service Implementation

@available(macOS 15.0, *)
struct CASProxyService: RegistrableRPCService {
    static let keyValueDBServiceDescriptor = ServiceDescriptor(
        package: "compilation_cache_service.keyvalue.v1", 
        service: "KeyValueDB"
    )
    
    enum Methods {
        static let getValue = MethodDescriptor(
            fullyQualifiedService: keyValueDBServiceDescriptor.fullyQualifiedService,
            method: "GetValue"
        )
    }
    
    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        let serializer = IdentitySerializer()
        let deserializer = IdentityDeserializer()
        
        print("🔧 Registering KeyValueDB service handlers...")
        
        // Register the official KeyValueDB.GetValue method
        router.registerHandler(
            forMethod: Methods.getValue,
            deserializer: deserializer,
            serializer: serializer
        ) { streamRequest, context in
            print("✅ KeyValueDB.GetValue called")
            let singleRequest = try await ServerRequest(stream: streamRequest)
            let response = try await self.handleGetValue(singleRequest)
            return StreamingServerResponse(single: response)
        }
        
        // Also register some fallback handlers for variations
        let fallbackMethods = [
            MethodDescriptor(fullyQualifiedService: "KeyValueDB", method: "GetValue"),
            MethodDescriptor(fullyQualifiedService: "compilation_cache_service.keyvalue.v1.KeyValueDB", method: "GetValue"),
            MethodDescriptor(fullyQualifiedService: "", method: "builtin-swiftCachingKeyQuery"),
            MethodDescriptor(fullyQualifiedService: "builtin-swiftCachingKeyQuery", method: "Query"),
        ]
        
        for method in fallbackMethods {
            print("  Registering fallback: '\(method.service)/\(method.method)'")
            
            router.registerHandler(
                forMethod: method,
                deserializer: deserializer,
                serializer: serializer
            ) { streamRequest, context in
                print("✅ Fallback handler triggered for: '\(method.service)/\(method.method)'")
                let singleRequest = try await ServerRequest(stream: streamRequest)
                let response = try await self.handleGetValue(singleRequest)
                return StreamingServerResponse(single: response)
            }
        }
        
        print("🔧 Handler registration complete!")
    }
    
    private func handleGetValue(_ request: ServerRequest<[UInt8]>) async throws -> ServerResponse<[UInt8]> {
        print("🔍 KeyValueDB.GetValue called")
        print("  Request metadata: \(request.metadata)")
        print("  Request message size: \(request.message.count) bytes")
        print("  Request message hex: \(Data(request.message).hexString)")
        
        do {
            print("  Decoding GetValueRequest...")
            // Parse the GetValueRequest
            let getValueRequest = try GetValueRequest.decode(from: Data(request.message))
            
            // The key is now a string
            print("  Cache key: \(getValueRequest.key)")
            print("  Cache key length: \(getValueRequest.key.count)")
            
            // For now, always return cache miss
            let response = GetValueResponse(found: false)
            let responseData = response.encode()
            
            print("  Sending GetValue response: found=false (cache miss)")
            return ServerResponse(message: Array(responseData), metadata: [:])
            
        } catch {
            print("  Error parsing request: \(error)")
            // Fallback to simple response
            let response = GetValueResponse(found: false)
            let responseData = response.encode()
            return ServerResponse(message: Array(responseData), metadata: [:])
        }
    }
    
    private func analyzeProtobufMessage(_ data: Data) {
        var index = 0
        var fieldCount = 0
        
        while index < data.count && fieldCount < 5 {
            guard index < data.count else { break }
            
            let tag = data[index]
            index += 1
            
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            
            switch wireType {
            case 0: // Varint
                let (value, newIndex) = readVarint(data, from: index)
                index = newIndex
                print("    field \(fieldNumber): varint = \(value)")
                
            case 2: // Length-delimited
                let (length, lengthEndIndex) = readVarint(data, from: index)
                index = lengthEndIndex
                
                if index + Int(length) <= data.count {
                    let fieldData = data[index..<index + Int(length)]
                    index += Int(length)
                    
                    if let string = String(data: fieldData, encoding: .utf8), string.allSatisfy({ $0.isPrintable }) {
                        print("    field \(fieldNumber): string = \"\(string.prefix(50))\"")
                    } else {
                        print("    field \(fieldNumber): bytes = \(fieldData.count) bytes")
                    }
                } else {
                    print("    field \(fieldNumber): invalid length-delimited field")
                    break
                }
                
            default:
                print("    field \(fieldNumber): unknown wire type \(wireType)")
                break
            }
            
            fieldCount += 1
        }
    }
    
    private func readVarint(_ data: Data, from startIndex: Int) -> (value: UInt64, endIndex: Int) {
        var value: UInt64 = 0
        var index = startIndex
        var shift = 0
        
        while index < data.count && shift < 64 {
            let byte = data[index]
            value |= UInt64(byte & 0x7F) << shift
            index += 1
            
            if byte & 0x80 == 0 {
                break
            }
            
            shift += 7
        }
        
        return (value, index)
    }
}

// MARK: - Protobuf Helper Functions

@available(macOS 15.0, *)
private func readVarint(_ data: Data, from startIndex: Int) -> (value: UInt64, endIndex: Int) {
    var value: UInt64 = 0
    var index = startIndex
    var shift = 0
    
    while index < data.count && shift < 64 {
        let byte = data[index]
        value |= UInt64(byte & 0x7F) << shift
        index += 1
        
        if byte & 0x80 == 0 {
            break
        }
        
        shift += 7
    }
    
    return (value, index)
}

@available(macOS 15.0, *)
private func encodeVarint(_ value: UInt64) -> [UInt8] {
    var value = value
    var result: [UInt8] = []
    
    while value >= 0x80 {
        result.append(UInt8(value & 0x7F) | 0x80)
        value >>= 7
    }
    
    result.append(UInt8(value))
    return result
}

// MARK: - Identity Serializers

@available(macOS 15.0, *)
struct IdentitySerializer: MessageSerializer {
    func serialize<Bytes: GRPCContiguousBytes>(_ message: [UInt8]) throws -> Bytes {
        return Bytes(message)
    }
}

@available(macOS 15.0, *)
struct IdentityDeserializer: MessageDeserializer {
    func deserialize<Bytes: GRPCContiguousBytes>(_ serializedMessageBytes: Bytes) throws -> [UInt8] {
        return serializedMessageBytes.withUnsafeBytes {
            Array($0)
        }
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
