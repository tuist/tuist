import Foundation
import Dispatch

@main
private enum TuistCASProxy {
    static func main() {
        print("Starting Tuist CAS Proxy...")
        
        // Ignore SIGPIPE to prevent process termination
        signal(SIGPIPE, SIG_IGN)
        
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
            try server.start()
            // Keep the main thread alive
            RunLoop.current.run()
        } catch {
            print("Error starting server: \(error)")
            exit(1)
        }
    }
}

class CASProxyServer {
    private let socketPath: String
    private var socketFileDescriptor: Int32 = -1
    private let queue = DispatchQueue(label: "cas.proxy.server", attributes: .concurrent)
    
    init(socketPath: String) {
        self.socketPath = socketPath
    }
    
    func start() throws {
        print("Creating Unix domain socket at: \(socketPath)")
        
        // Create Unix domain socket
        socketFileDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard socketFileDescriptor >= 0 else {
            throw ProxyError.socketCreationFailed(errno: errno)
        }
        
        // Set socket options for reuse
        var reuseOn = Int32(1)
        setsockopt(socketFileDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuseOn, socklen_t(MemoryLayout<Int32>.size))
        
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
        
        // Listen for connections with higher backlog
        guard listen(socketFileDescriptor, 128) >= 0 else {
            close(socketFileDescriptor)
            throw ProxyError.listenFailed(errno: errno)
        }
        
        print("Listening on \(socketPath)")
        
        // Start accepting connections in background
        queue.async {
            self.acceptLoop()
        }
    }
    
    private func acceptLoop() {
        print("Starting accept loop...")
        var connectionCount = 0
        
        while true {
            var clientAddr = sockaddr_un()
            var clientAddrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            
            let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                    accept(socketFileDescriptor, sockaddrPtr, &clientAddrLen)
                }
            }
            
            if clientSocket < 0 {
                if errno != EINTR {
                    print("Error accepting connection: \(errno) - \(String(cString: strerror(errno)))")
                }
                continue
            }
            
            connectionCount += 1
            let currentConnectionId = connectionCount
            print("\n[Connection #\(currentConnectionId)] Accepted, fd=\(clientSocket)")
            
            // Handle each client in a separate concurrent queue task
            queue.async {
                self.handleClient(socket: clientSocket, connectionId: currentConnectionId)
            }
        }
    }
    
    private func handleClient(socket: Int32, connectionId: Int) {
        print("[Connection #\(connectionId)] Handling client on thread: \(Thread.current)")
        
        // Set socket options for better performance
        var noDelay = Int32(1)
        setsockopt(socket, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))
        
        // Set a longer timeout to keep connections alive
        var timeout = timeval()
        timeout.tv_sec = 300  // 5 minutes
        timeout.tv_usec = 0
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
        // Set keepalive to maintain connection
        var keepAlive = Int32(1)
        setsockopt(socket, SOL_SOCKET, SO_KEEPALIVE, &keepAlive, socklen_t(MemoryLayout<Int32>.size))
        
        // Try to read initial data
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = recv(socket, &buffer, buffer.count, 0)
        
        if bytesRead > 0 {
            print("[Connection #\(connectionId)] Received \(bytesRead) bytes")
            let data = Data(bytes: buffer, count: bytesRead)
            
            // Check if it's HTTP/2 preface
            if bytesRead >= 24 {
                let preface = String(data: data.prefix(24), encoding: .ascii) ?? ""
                if preface == "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n" {
                    print("[Connection #\(connectionId)] Detected HTTP/2 preface")
                    handleHTTP2Connection(socket: socket, connectionId: connectionId, initialData: data)
                    return
                }
            }
            
            // Otherwise, show what we got
            print("[Connection #\(connectionId)] Data hex: \(data.prefix(100).hexEncodedString())")
            if let str = String(data: data, encoding: .utf8) {
                print("[Connection #\(connectionId)] Data string: \(str.prefix(100))")
            }
        } else if bytesRead == 0 {
            print("[Connection #\(connectionId)] Connection closed by peer")
        } else {
            print("[Connection #\(connectionId)] recv error: \(errno) - \(String(cString: strerror(errno)))")
        }
        
        close(socket)
        print("[Connection #\(connectionId)] Closed")
    }
    
    private func handleHTTP2Connection(socket: Int32, connectionId: Int, initialData: Data) {
        print("[Connection #\(connectionId)] Starting HTTP/2 handler")
        
        // Send HTTP/2 SETTINGS frame immediately
        let settingsFrame = createHTTP2Frame(type: 0x04, flags: 0x00, streamId: 0, payload: Data())
        let settingsSent = settingsFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, settingsFrame.count, MSG_NOSIGNAL)
        }
        if settingsSent < 0 {
            print("[Connection #\(connectionId)] Failed to send SETTINGS frame")
            return
        }
        print("[Connection #\(connectionId)] Sent SETTINGS frame")
        
        // Track accumulated data per stream
        var streamData: [UInt32: Data] = [:]
        
        // Process remaining data after preface
        var buffer = [UInt8](initialData.dropFirst(24))
        
        while true {
            // Read more data if needed
            if buffer.count < 9 {
                var readBuffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = recv(socket, &readBuffer, readBuffer.count, 0)
                
                if bytesRead > 0 {
                    buffer.append(contentsOf: readBuffer[0..<bytesRead])
                } else if bytesRead == 0 {
                    print("[Connection #\(connectionId)] Connection closed by client")
                    break
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(1000) // 1ms
                    continue
                } else if errno == ETIMEDOUT {
                    print("[Connection #\(connectionId)] Socket timeout - keeping connection alive")
                    continue
                } else {
                    print("[Connection #\(connectionId)] recv error: \(errno) - \(String(cString: strerror(errno)))")
                    break
                }
            }
            
            // Parse HTTP/2 frame header
            if buffer.count >= 9 {
                let frameLength = Int(buffer[0]) << 16 | Int(buffer[1]) << 8 | Int(buffer[2])
                let frameType = buffer[3]
                let frameFlags = buffer[4]
                let streamId = UInt32(buffer[5] & 0x7F) << 24 |
                              UInt32(buffer[6]) << 16 |
                              UInt32(buffer[7]) << 8 |
                              UInt32(buffer[8])
                
                // Only log non-data frames or first data frame of a stream
                if frameType != 0x00 {
                    print("[Connection #\(connectionId)] Frame: type=\(frameType), flags=\(frameFlags), streamId=\(streamId), length=\(frameLength)")
                }
                
                // Wait for full frame
                if buffer.count < 9 + frameLength {
                    continue
                }
                
                // Extract frame payload safely
                let framePayload = Data(buffer[9..<9+frameLength])
                buffer.removeFirst(9 + frameLength)
                
                // Handle frame based on type
                switch frameType {
                case 0x00: // DATA
                    handleDataFrame(socket: socket, connectionId: connectionId, streamId: streamId, flags: frameFlags, payload: framePayload, streamData: &streamData)
                case 0x01: // HEADERS
                    handleHeadersFrame(socket: socket, connectionId: connectionId, streamId: streamId, flags: frameFlags, payload: framePayload)
                case 0x04: // SETTINGS
                    if frameFlags & 0x01 == 0 {
                        // Send SETTINGS ACK
                        let ackFrame = createHTTP2Frame(type: 0x04, flags: 0x01, streamId: 0, payload: Data())
                        let ackSent = ackFrame.withUnsafeBytes { bytes in
                            send(socket, bytes.baseAddress, ackFrame.count, MSG_NOSIGNAL)
                        }
                        if ackSent >= 0 {
                            print("[Connection #\(connectionId)] Sent SETTINGS ACK")
                        }
                    }
                case 0x06: // PING
                    if frameFlags & 0x01 == 0 {
                        // Echo PING with ACK
                        let pingAck = createHTTP2Frame(type: 0x06, flags: 0x01, streamId: 0, payload: framePayload)
                        let pingSent = pingAck.withUnsafeBytes { bytes in
                            send(socket, bytes.baseAddress, pingAck.count, MSG_NOSIGNAL)
                        }
                        if pingSent >= 0 {
                            print("[Connection #\(connectionId)] Sent PING ACK")
                        }
                    }
                case 0x08: // WINDOW_UPDATE
                    print("[Connection #\(connectionId)] WINDOW_UPDATE")
                default:
                    print("[Connection #\(connectionId)] Unhandled frame type: \(frameType)")
                }
            }
        }
        
        close(socket)
        print("[Connection #\(connectionId)] HTTP/2 connection closed")
    }
    
    private func handleHeadersFrame(socket: Int32, connectionId: Int, streamId: UInt32, flags: UInt8, payload: Data) {
        print("[Connection #\(connectionId)] Stream \(streamId) - HEADERS frame, \(payload.count) bytes")
        print("[Connection #\(connectionId)] Headers hex: \(payload.hexEncodedString())")
        
        // For now, prepare to handle the request
        // In a real implementation, we'd decode HPACK headers here
    }
    
    private func handleDataFrame(socket: Int32, connectionId: Int, streamId: UInt32, flags: UInt8, payload: Data, streamData: inout [UInt32: Data]) {
        let isEndStream = flags & 0x01 != 0
        
        // Accumulate data for this stream
        if streamData[streamId] == nil {
            streamData[streamId] = Data()
            print("[Connection #\(connectionId)] Stream \(streamId) - Starting new data stream")
        }
        streamData[streamId]!.append(payload)
        
        let totalSize = streamData[streamId]!.count
        
        // Only log every 10th frame to reduce noise, or when ending
        let frameCount = totalSize / 16384
        if isEndStream || frameCount % 10 == 0 {
            print("[Connection #\(connectionId)] Stream \(streamId) - DATA frame \(payload.count) bytes (total: \(totalSize) bytes, frames: ~\(frameCount), endStream: \(isEndStream))")
        }
        
        // Only process when we have the complete stream
        if isEndStream {
            let completeData = streamData[streamId]!
            streamData[streamId] = nil // Clean up
            
            print("[Connection #\(connectionId)] Stream \(streamId) - COMPLETE: \(completeData.count) bytes total")
            
            // Check if this is a gRPC message
            if completeData.count >= 5 {
                let compressed = completeData[0]
                let messageLength = UInt32(completeData[1]) << 24 | UInt32(completeData[2]) << 16 |
                                   UInt32(completeData[3]) << 8 | UInt32(completeData[4])
                
                print("[Connection #\(connectionId)] gRPC: compressed=\(compressed), declared_length=\(messageLength), actual_total=\(completeData.count)")
                
                if completeData.count >= 5 + messageLength {
                    let messageData = completeData.subdata(in: 5..<5+Int(messageLength))
                    print("[Connection #\(connectionId)] Message (first 100 bytes): \(messageData.prefix(100).hexEncodedString())")
                    
                    // Try to decode basic protobuf fields to understand the request type
                    analyzeProtobufMessage(data: messageData, connectionId: connectionId)
                    
                    // Determine response type based on message size and content
                    if messageLength > 100 {
                        print("[Connection #\(connectionId)] → Sending Save response (large message)")
                        sendSaveResponse(socket: socket, connectionId: connectionId, streamId: streamId)
                    } else {
                        print("[Connection #\(connectionId)] → Sending GetValue response (small message)")
                        sendGetValueResponse(socket: socket, connectionId: connectionId, streamId: streamId)
                    }
                } else {
                    print("[Connection #\(connectionId)] Incomplete gRPC message (expected \(messageLength + 5), got \(completeData.count))")
                    sendGetValueResponse(socket: socket, connectionId: connectionId, streamId: streamId)
                }
            } else if completeData.count == 0 {
                print("[Connection #\(connectionId)] → Empty stream, sending GetValue response")
                sendGetValueResponse(socket: socket, connectionId: connectionId, streamId: streamId)
            } else {
                print("[Connection #\(connectionId)] Invalid gRPC format (too short: \(completeData.count) bytes)")
                print("[Connection #\(connectionId)] Raw data: \(completeData.prefix(20).hexEncodedString())")
                sendGetValueResponse(socket: socket, connectionId: connectionId, streamId: streamId)
            }
        }
    }
    
    private func analyzeProtobufMessage(data: Data, connectionId: Int) {
        print("[Connection #\(connectionId)] Protobuf analysis:")
        var index = 0
        var fieldCount = 0
        
        while index < data.count && fieldCount < 5 { // Limit to first 5 fields
            guard index < data.count else { break }
            
            let tag = data[index]
            index += 1
            
            let fieldNumber = tag >> 3
            let wireType = tag & 0x07
            
            switch wireType {
            case 0: // Varint
                let (value, newIndex) = readVarint(data, from: index)
                index = newIndex
                print("[Connection #\(connectionId)]   field \(fieldNumber): varint = \(value)")
                
            case 2: // Length-delimited
                let (length, lengthEndIndex) = readVarint(data, from: index)
                index = lengthEndIndex
                
                if index + Int(length) <= data.count {
                    let fieldData = data[index..<index + Int(length)]
                    index += Int(length)
                    
                    if let string = String(data: fieldData, encoding: .utf8), string.allSatisfy({ $0.isPrintable }) {
                        print("[Connection #\(connectionId)]   field \(fieldNumber): string = \"\(string.prefix(50))\"")
                    } else {
                        print("[Connection #\(connectionId)]   field \(fieldNumber): bytes = \(fieldData.count) bytes (\(fieldData.prefix(20).hexEncodedString())...)")
                    }
                } else {
                    print("[Connection #\(connectionId)]   field \(fieldNumber): invalid length-delimited field")
                    break
                }
                
            default:
                print("[Connection #\(connectionId)]   field \(fieldNumber): unknown wire type \(wireType)")
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
    
    private func sendGetValueResponse(socket: Int32, connectionId: Int, streamId: UInt32) {
        print("[Connection #\(connectionId)] Sending GetValue response for stream \(streamId)")
        
        // Send HEADERS frame with minimal HPACK encoding
        var headersData = Data()
        headersData.append(0x88) // :status = 200 (indexed header field from static table)
        
        let headersFrame = createHTTP2Frame(type: 0x01, flags: 0x04, streamId: streamId, payload: headersData) // END_HEADERS
        let headersSent = headersFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, headersFrame.count, MSG_NOSIGNAL)
        }
        
        if headersSent < 0 {
            print("[Connection #\(connectionId)] Failed to send headers, connection likely closed")
            return
        }
        
        // Create GetValue response (not found)
        var response = Data()
        response.append(0x08) // field 1, wire type 0 (varint)
        response.append(0x00) // found = false
        
        // Wrap in gRPC message
        var grpcMessage = Data()
        grpcMessage.append(0x00) // not compressed
        var length = UInt32(response.count).bigEndian
        grpcMessage.append(Data(bytes: &length, count: 4))
        grpcMessage.append(response)
        
        // Send DATA frame with the gRPC message
        let dataFrame = createHTTP2Frame(type: 0x00, flags: 0x00, streamId: streamId, payload: grpcMessage)
        let dataSent = dataFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, dataFrame.count, MSG_NOSIGNAL)
        }
        
        if dataSent < 0 {
            print("[Connection #\(connectionId)] Failed to send data, connection likely closed")
            return
        }
        
        // Send gRPC trailers with proper HPACK encoding
        var trailersData = Data()
        // grpc-status: 0 (OK) - using literal header field without indexing
        trailersData.append(0x00) // literal header field without indexing
        trailersData.append(0x0b) // name length: 11
        trailersData.append("grpc-status".data(using: .ascii)!) // name
        trailersData.append(0x01) // value length: 1
        trailersData.append("0".data(using: .ascii)!) // value: 0 (OK)
        
        let trailersFrame = createHTTP2Frame(type: 0x01, flags: 0x05, streamId: streamId, payload: trailersData) // END_HEADERS | END_STREAM
        let trailersSent = trailersFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, trailersFrame.count, MSG_NOSIGNAL)
        }
        
        if trailersSent < 0 {
            print("[Connection #\(connectionId)] Failed to send trailers, connection likely closed")
            return
        }
        
        print("[Connection #\(connectionId)] GetValue response sent for stream \(streamId)")
    }
    
    private func sendSaveResponse(socket: Int32, connectionId: Int, streamId: UInt32) {
        print("[Connection #\(connectionId)] Sending Save response for stream \(streamId)")
        
        // Send HEADERS frame with minimal HPACK encoding
        var headersData = Data()
        headersData.append(0x88) // :status = 200 (indexed header field from static table)
        
        let headersFrame = createHTTP2Frame(type: 0x01, flags: 0x04, streamId: streamId, payload: headersData) // END_HEADERS
        let headersSent = headersFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, headersFrame.count, MSG_NOSIGNAL)
        }
        
        if headersSent < 0 {
            print("[Connection #\(connectionId)] Failed to send headers, connection likely closed")
            return
        }
        
        // Create Save response (success)
        var response = Data()
        // Field 1 (cas_id): tag = (1 << 3) | 2 = 10, wire type 2 (length-delimited)
        response.append(0x0A)
        let casId = "fake-cas-id"
        response.append(UInt8(casId.count))
        response.append(casId.data(using: .utf8)!)
        
        // Field 2 (success): tag = (2 << 3) | 0 = 16, wire type 0 (varint)
        response.append(0x10)
        response.append(0x01) // success = true
        
        // Wrap in gRPC message
        var grpcMessage = Data()
        grpcMessage.append(0x00) // not compressed
        var length = UInt32(response.count).bigEndian
        grpcMessage.append(Data(bytes: &length, count: 4))
        grpcMessage.append(response)
        
        // Send DATA frame with the gRPC message
        let dataFrame = createHTTP2Frame(type: 0x00, flags: 0x00, streamId: streamId, payload: grpcMessage)
        let dataSent = dataFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, dataFrame.count, MSG_NOSIGNAL)
        }
        
        if dataSent < 0 {
            print("[Connection #\(connectionId)] Failed to send data, connection likely closed")
            return
        }
        
        // Send gRPC trailers with proper HPACK encoding
        var trailersData = Data()
        // grpc-status: 0 (OK) - using literal header field without indexing
        trailersData.append(0x00) // literal header field without indexing
        trailersData.append(0x0b) // name length: 11
        trailersData.append("grpc-status".data(using: .ascii)!) // name
        trailersData.append(0x01) // value length: 1
        trailersData.append("0".data(using: .ascii)!) // value: 0 (OK)
        
        let trailersFrame = createHTTP2Frame(type: 0x01, flags: 0x05, streamId: streamId, payload: trailersData) // END_HEADERS | END_STREAM
        let trailersSent = trailersFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, trailersFrame.count, MSG_NOSIGNAL)
        }
        
        if trailersSent < 0 {
            print("[Connection #\(connectionId)] Failed to send trailers, connection likely closed")
            return
        }
        
        print("[Connection #\(connectionId)] Save response sent for stream \(streamId)")
    }
    
    private func createHTTP2Frame(type: UInt8, flags: UInt8, streamId: UInt32, payload: Data) -> Data {
        var frame = Data()
        
        // Length (3 bytes)
        let length = payload.count
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        
        // Type and flags
        frame.append(type)
        frame.append(flags)
        
        // Stream ID (4 bytes)
        frame.append(UInt8((streamId >> 24) & 0x7F))
        frame.append(UInt8((streamId >> 16) & 0xFF))
        frame.append(UInt8((streamId >> 8) & 0xFF))
        frame.append(UInt8(streamId & 0xFF))
        
        // Payload
        frame.append(payload)
        
        return frame
    }
}

enum ProxyError: Error {
    case socketCreationFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
}

extension Data {
    func hexEncodedString() -> String {
        return map { String(format: "%02hhx", $0) }.joined()
    }
}

extension Character {
    var isPrintable: Bool {
        return isASCII && (isLetter || isNumber || isPunctuation || isSymbol || isWhitespace)
    }
}
