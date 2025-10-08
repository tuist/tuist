import Foundation

@main
struct TuistCASProxy {
    static func main() async {
        print("Starting Tuist CAS Proxy...")
        
        let socketPath: String
        if CommandLine.arguments.count > 1 {
            socketPath = CommandLine.arguments[1]
        } else {
            socketPath = "cas.sock"
        }
        
        // Remove existing socket file if it exists
        try? FileManager.default.removeItem(atPath: socketPath)
        
        let server = CASProxyServer(socketPath: socketPath)
        
        do {
            try await server.start()
        } catch {
            print("Error starting server: \(error)")
            exit(1)
        }
    }
}

actor CASProxyServer {
    private let socketPath: String
    private var socketFileDescriptor: Int32 = -1
    
    init(socketPath: String) {
        self.socketPath = socketPath
    }
    
    func start() async throws {
        print("Creating Unix domain socket at: \(socketPath)")
        
        // Create Unix domain socket
        socketFileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFileDescriptor >= 0 else {
            throw ProxyError.socketCreationFailed(errno: errno)
        }
        
        // Configure socket address
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        
        // Initialize sun_path to zero
        withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            ptr.withMemoryRebound(to: Int8.self, capacity: 104) { pathPtr in
                for i in 0..<104 {
                    pathPtr[i] = 0
                }
                
                // Copy socket path
                socketPath.withCString { socketPathCString in
                    let length = min(socketPath.count, 103) // Leave room for null terminator
                    for i in 0..<length {
                        pathPtr[i] = socketPathCString[i]
                    }
                }
            }
        }
        
        // Bind socket
        let bindResult = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(socketFileDescriptor, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        
        guard bindResult >= 0 else {
            close(socketFileDescriptor)
            throw ProxyError.bindFailed(errno: errno)
        }
        
        // Listen for connections
        guard listen(socketFileDescriptor, 5) >= 0 else {
            close(socketFileDescriptor)
            throw ProxyError.listenFailed(errno: errno)
        }
        
        print("Listening on \(socketPath)")
        
        // Accept connections
        await acceptConnections()
    }
    
    private func acceptConnections() async {
        print("Starting to accept connections...")
        var connectionCount = 0
        
        while true {
            print("Waiting for connection \(connectionCount + 1)...")
            let clientSocket = accept(socketFileDescriptor, nil, nil)
            if clientSocket < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    // Non-blocking socket, no connection available
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    continue
                }
                print("Error accepting connection: \(errno) - \(String(cString: strerror(errno)))")
                continue
            }
            
            connectionCount += 1
            print("Accepted connection #\(connectionCount), socket: \(clientSocket)")
            
            Task {
                await handleClient(socket: clientSocket)
            }
        }
    }
    
    private func handleClient(socket: Int32) async {
        print("\n=== New client connected ===")
        print("Socket descriptor: \(socket)")
        
        // Set socket to non-blocking mode for better debugging
        var flags = fcntl(socket, F_GETFL, 0)
        if flags != -1 {
            fcntl(socket, F_SETFL, flags | O_NONBLOCK)
        }
        
        let connection = HTTP2Connection(socket: socket)
        
        do {
            try await connection.handleConnection()
        } catch {
            print("Error handling client: \(error)")
            print("Error details: \(String(describing: error))")
        }
        
        close(socket)
        print("=== Client disconnected ===\n")
    }
}

class HTTP2Connection {
    private let socket: Int32
    private let reader: SocketReader
    private var streamStates: [UInt32: StreamState] = [:]
    
    struct StreamState {
        var headers: [String: String] = [:]
        var data: Data = Data()
    }
    
    init(socket: Int32) {
        self.socket = socket
        self.reader = SocketReader(socket: socket)
    }
    
    func handleConnection() async throws {
        print("Starting to handle connection...")
        
        // Try to read initial data to see what we're getting
        print("Attempting to read initial bytes...")
        
        do {
            // Try to peek at the first few bytes
            let initialBytes = try await reader.readExactly(1)
            print("First byte: 0x\(String(format: "%02X", initialBytes[0]))")
            
            // Check if this looks like HTTP/2
            if initialBytes[0] == 0x50 { // 'P' from "PRI"
                print("Detected HTTP/2 preface start")
                // Read the rest of the preface
                let restOfPreface = try await reader.readExactly(23)
                let fullPreface = initialBytes + restOfPreface
                let prefaceString = String(data: fullPreface, encoding: .ascii) ?? ""
                print("Received preface: \(prefaceString.debugDescription)")
                print("Preface hex: \(fullPreface.hexEncodedString())")
                
                if prefaceString != "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" {
                    print("Invalid HTTP/2 preface!")
                    throw ProxyError.invalidHTTP2Preface
                }
                
                print("Valid HTTP/2 preface received")
                
                // Send initial SETTINGS frame
                print("Sending SETTINGS frame...")
                try await sendSettingsFrame()
                
                // Process frames
                while true {
                    print("\nWaiting for next frame...")
                    guard let frame = try await readHTTP2Frame() else {
                        print("No more frames, connection closing")
                        break
                    }
                    
                    try await handleFrame(frame)
                }
            } else {
                print("Unexpected first byte, not HTTP/2")
                print("Reading more data to understand protocol...")
                
                // Read more data to see what this is
                let moreData = try await reader.readExactly(100)
                let allData = initialBytes + moreData
                print("Raw data (first 101 bytes): \(allData.hexEncodedString())")
                if let str = String(data: allData, encoding: .utf8) {
                    print("As string: \(str.debugDescription)")
                }
            }
        } catch {
            print("Error during initial connection handling: \(error)")
            throw error
        }
    }
    
    private func readHTTP2Frame() async throws -> HTTP2Frame? {
        // Read frame header (9 bytes)
        guard let headerData = try? await reader.readExactly(9) else {
            return nil
        }
        
        // Parse frame header
        let length = Int(headerData[0]) << 16 | Int(headerData[1]) << 8 | Int(headerData[2])
        let type = HTTP2FrameType(rawValue: headerData[3]) ?? .unknown
        let flags = headerData[4]
        let streamId = UInt32(headerData[5] & 0x7F) << 24 | UInt32(headerData[6]) << 16 |
                      UInt32(headerData[7]) << 8 | UInt32(headerData[8])
        
        // Read payload
        let payload = length > 0 ? try await reader.readExactly(length) : Data()
        
        return HTTP2Frame(type: type, flags: flags, streamId: streamId, payload: payload)
    }
    
    private func handleFrame(_ frame: HTTP2Frame) async throws {
        print("Received frame: type=\(frame.type), streamId=\(frame.streamId), flags=\(frame.flags), length=\(frame.payload.count)")
        
        switch frame.type {
        case .settings:
            if frame.flags & 0x01 == 0 { // Not ACK
                // Send SETTINGS ACK
                try await sendFrame(HTTP2Frame(type: .settings, flags: 0x01, streamId: 0, payload: Data()))
            }
            
        case .headers:
            // Initialize stream state
            streamStates[frame.streamId] = StreamState()
            
            // Parse headers (simplified - should use HPACK)
            print("HEADERS frame for stream \(frame.streamId)")
            print("Raw headers: \(frame.payload.hexEncodedString())")
            
        case .data:
            if var state = streamStates[frame.streamId] {
                state.data.append(frame.payload)
                streamStates[frame.streamId] = state
                
                print("DATA frame for stream \(frame.streamId): \(frame.payload.count) bytes")
                
                // Check if this is the end of the stream
                if frame.flags & 0x01 != 0 { // END_STREAM
                    try await handleGRPCRequest(streamId: frame.streamId, data: state.data)
                    streamStates[frame.streamId] = nil
                }
            }
            
        case .windowUpdate:
            print("WINDOW_UPDATE frame")
            
        case .ping:
            if frame.flags & 0x01 == 0 { // Not ACK
                // Send PING ACK
                try await sendFrame(HTTP2Frame(type: .ping, flags: 0x01, streamId: 0, payload: frame.payload))
            }
            
        default:
            print("Unhandled frame type: \(frame.type.rawValue)")
        }
    }
    
    private func handleGRPCRequest(streamId: UInt32, data: Data) async throws {
        print("\nProcessing gRPC request for stream \(streamId)")
        
        // Parse gRPC message
        guard data.count >= 5 else {
            print("Invalid gRPC message: too short")
            return
        }
        
        let compressed = data[0] != 0
        let messageLength = UInt32(data[1]) << 24 | UInt32(data[2]) << 16 |
                           UInt32(data[3]) << 8 | UInt32(data[4])
        let messageData = data.subdata(in: 5..<data.count)
        
        print("gRPC message: compressed=\(compressed), length=\(messageLength)")
        
        // Decode protobuf
        let decoded = try decodeProtobufMessage(messageData)
        print("Decoded message: \(decoded)")
        
        // Determine request type and send response
        if decoded.keys.contains(where: { $0.contains("cas_id") }) || 
           decoded.keys.contains(where: { $0.contains("data") }) {
            print("Detected Save request")
            try await sendSaveResponse(streamId: streamId)
        } else {
            print("Detected GetValue request")
            try await sendGetValueResponse(streamId: streamId)
        }
    }
    
    private func sendGetValueResponse(streamId: UInt32) async throws {
        print("Sending GetValue response for stream \(streamId)")
        
        // Create protobuf response
        var response = Data()
        
        // Field 1 (found): tag = (1 << 3) | 0 = 8, wire type 0 (varint)
        response.append(0x08)
        response.append(0x00) // found = false
        
        // Send response
        try await sendGRPCResponse(streamId: streamId, data: response, endStream: true)
    }
    
    private func sendSaveResponse(streamId: UInt32) async throws {
        print("Sending Save response for stream \(streamId)")
        
        // Create protobuf response
        var response = Data()
        
        // Field 1 (cas_id): tag = (1 << 3) | 2 = 10, wire type 2 (length-delimited)
        response.append(0x0A)
        let casId = "fake-cas-id"
        response.append(UInt8(casId.count))
        response.append(casId.data(using: .utf8)!)
        
        // Field 2 (success): tag = (2 << 3) | 0 = 16, wire type 0 (varint)
        response.append(0x10)
        response.append(0x01) // success = true
        
        // Send response
        try await sendGRPCResponse(streamId: streamId, data: response, endStream: true)
    }
    
    private func sendGRPCResponse(streamId: UInt32, data: Data, endStream: Bool) async throws {
        // Send HEADERS frame first (minimal headers)
        let headersPayload = Data([
            0x88, // :status = 200 (indexed header field)
        ])
        try await sendFrame(HTTP2Frame(type: .headers, flags: 0x04, streamId: streamId, payload: headersPayload))
        
        // Create gRPC message
        var grpcMessage = Data()
        grpcMessage.append(0x00) // Not compressed
        var length = UInt32(data.count).bigEndian
        grpcMessage.append(Data(bytes: &length, count: 4))
        grpcMessage.append(data)
        
        // Send DATA frame
        let flags: UInt8 = endStream ? 0x01 : 0x00
        try await sendFrame(HTTP2Frame(type: .data, flags: flags, streamId: streamId, payload: grpcMessage))
    }
    
    private func sendSettingsFrame() async throws {
        // Empty SETTINGS frame
        try await sendFrame(HTTP2Frame(type: .settings, flags: 0x00, streamId: 0, payload: Data()))
    }
    
    private func sendFrame(_ frame: HTTP2Frame) async throws {
        var data = Data()
        
        // Frame header (9 bytes)
        // Length (3 bytes)
        data.append(UInt8((frame.payload.count >> 16) & 0xFF))
        data.append(UInt8((frame.payload.count >> 8) & 0xFF))
        data.append(UInt8(frame.payload.count & 0xFF))
        
        // Type (1 byte)
        data.append(frame.type.rawValue)
        
        // Flags (1 byte)
        data.append(frame.flags)
        
        // Stream ID (4 bytes)
        data.append(UInt8((frame.streamId >> 24) & 0x7F))
        data.append(UInt8((frame.streamId >> 16) & 0xFF))
        data.append(UInt8((frame.streamId >> 8) & 0xFF))
        data.append(UInt8(frame.streamId & 0xFF))
        
        // Payload
        data.append(frame.payload)
        
        _ = data.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, data.count, 0)
        }
    }
    
    private func decodeProtobufMessage(_ data: Data) throws -> [String: Any] {
        var result: [String: Any] = [:]
        var index = 0
        
        while index < data.count {
            guard index < data.count else { break }
            
            let tag = data[index]
            index += 1
            
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            
            print("  Field \(fieldNumber), wire type \(wireType)")
            
            switch wireType {
            case 0: // Varint
                let (value, newIndex) = readVarint(data, from: index)
                index = newIndex
                result["field_\(fieldNumber)"] = value
                print("    Varint value: \(value)")
                
            case 2: // Length-delimited
                let (length, lengthEndIndex) = readVarint(data, from: index)
                index = lengthEndIndex
                
                if index + Int(length) <= data.count {
                    let fieldData = data[index..<index + Int(length)]
                    index += Int(length)
                    
                    // Try to decode as string
                    if let string = String(data: fieldData, encoding: .utf8) {
                        result["field_\(fieldNumber)"] = string
                        print("    String value: \(string)")
                    } else {
                        result["field_\(fieldNumber)"] = fieldData
                        print("    Binary data: \(fieldData.count) bytes")
                    }
                }
                
            default:
                print("  Unknown wire type: \(wireType)")
                break
            }
        }
        
        return result
    }
    
    private func readVarint(_ data: Data, from startIndex: Int) -> (value: UInt64, endIndex: Int) {
        var value: UInt64 = 0
        var index = startIndex
        var shift = 0
        
        while index < data.count {
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

class SocketReader {
    private let socket: Int32
    private var buffer = Data()
    
    init(socket: Int32) {
        self.socket = socket
    }
    
    func readExactly(_ count: Int) async throws -> Data {
        print("  readExactly: need \(count) bytes, have \(buffer.count) in buffer")
        
        while buffer.count < count {
            var tempBuffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = recv(socket, &tempBuffer, tempBuffer.count, 0)
            
            if bytesRead > 0 {
                print("  readExactly: read \(bytesRead) bytes from socket")
                buffer.append(contentsOf: tempBuffer[0..<bytesRead])
                print("  readExactly: buffer now has \(buffer.count) bytes")
            } else if bytesRead == 0 {
                print("  readExactly: connection closed (recv returned 0)")
                throw ProxyError.connectionClosed
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                // Non-blocking socket, no data available yet
                print("  readExactly: would block, waiting...")
                try await Task.sleep(nanoseconds: 10_000_000) // 10ms
            } else {
                print("  readExactly: recv error \(errno)")
                throw ProxyError.readError(errno: errno)
            }
        }
        
        let result = buffer.prefix(count)
        buffer.removeFirst(count)
        print("  readExactly: returning \(result.count) bytes")
        return Data(result)
    }
}

struct HTTP2Frame {
    let type: HTTP2FrameType
    let flags: UInt8
    let streamId: UInt32
    let payload: Data
}

enum HTTP2FrameType: UInt8 {
    case data = 0x0
    case headers = 0x1
    case priority = 0x2
    case rstStream = 0x3
    case settings = 0x4
    case pushPromise = 0x5
    case ping = 0x6
    case goaway = 0x7
    case windowUpdate = 0x8
    case continuation = 0x9
    case unknown = 0xFF
}

enum ProxyError: Error {
    case socketCreationFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
    case connectionClosed
    case readError(errno: Int32)
    case invalidHTTP2Preface
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}