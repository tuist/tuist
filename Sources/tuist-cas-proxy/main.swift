import Foundation
import Dispatch

@main
struct TuistCASProxy {
    static func main() {
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
            print("\n[Connection #\(connectionCount)] Accepted, fd=\(clientSocket)")
            
            // Handle each client in a separate concurrent queue task
            queue.async {
                self.handleClient(socket: clientSocket, connectionId: connectionCount)
            }
        }
    }
    
    private func handleClient(socket: Int32, connectionId: Int) {
        print("[Connection #\(connectionId)] Handling client on thread: \(Thread.current)")
        
        // Set socket options for better performance
        var noDelay = Int32(1)
        setsockopt(socket, IPPROTO_TCP, TCP_NODELAY, &noDelay, socklen_t(MemoryLayout<Int32>.size))
        
        // Set a reasonable timeout
        var timeout = timeval()
        timeout.tv_sec = 30  // 30 seconds
        timeout.tv_usec = 0
        setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        
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
        _ = settingsFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, settingsFrame.count, 0)
        }
        print("[Connection #\(connectionId)] Sent SETTINGS frame")
        
        // Process remaining data after preface
        var remainingData = initialData.dropFirst(24)
        
        while true {
            // Read more data if needed
            if remainingData.count < 9 {
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = recv(socket, &buffer, buffer.count, 0)
                
                if bytesRead > 0 {
                    remainingData.append(contentsOf: buffer[0..<bytesRead])
                } else if bytesRead == 0 {
                    print("[Connection #\(connectionId)] Connection closed")
                    break
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(1000) // 1ms
                    continue
                } else {
                    print("[Connection #\(connectionId)] recv error: \(errno)")
                    break
                }
            }
            
            // Parse HTTP/2 frame header
            if remainingData.count >= 9 {
                let frameLength = Int(remainingData[0]) << 16 | Int(remainingData[1]) << 8 | Int(remainingData[2])
                let frameType = remainingData[3]
                let frameFlags = remainingData[4]
                let streamId = UInt32(remainingData[5] & 0x7F) << 24 |
                              UInt32(remainingData[6]) << 16 |
                              UInt32(remainingData[7]) << 8 |
                              UInt32(remainingData[8])
                
                print("[Connection #\(connectionId)] Frame: type=\(frameType), flags=\(frameFlags), streamId=\(streamId), length=\(frameLength)")
                
                // Wait for full frame
                if remainingData.count < 9 + frameLength {
                    continue
                }
                
                // Extract frame payload
                let framePayload = remainingData.subdata(in: 9..<9+frameLength)
                remainingData = remainingData.dropFirst(9 + frameLength)
                
                // Handle frame based on type
                switch frameType {
                case 0x00: // DATA
                    handleDataFrame(socket: socket, connectionId: connectionId, streamId: streamId, flags: frameFlags, payload: framePayload)
                case 0x01: // HEADERS
                    handleHeadersFrame(socket: socket, connectionId: connectionId, streamId: streamId, flags: frameFlags, payload: framePayload)
                case 0x04: // SETTINGS
                    if frameFlags & 0x01 == 0 {
                        // Send SETTINGS ACK
                        let ackFrame = createHTTP2Frame(type: 0x04, flags: 0x01, streamId: 0, payload: Data())
                        _ = ackFrame.withUnsafeBytes { bytes in
                            send(socket, bytes.baseAddress, ackFrame.count, 0)
                        }
                        print("[Connection #\(connectionId)] Sent SETTINGS ACK")
                    }
                case 0x06: // PING
                    if frameFlags & 0x01 == 0 {
                        // Echo PING with ACK
                        let pingAck = createHTTP2Frame(type: 0x06, flags: 0x01, streamId: 0, payload: framePayload)
                        _ = pingAck.withUnsafeBytes { bytes in
                            send(socket, bytes.baseAddress, pingAck.count, 0)
                        }
                        print("[Connection #\(connectionId)] Sent PING ACK")
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
    
    private func handleDataFrame(socket: Int32, connectionId: Int, streamId: UInt32, flags: UInt8, payload: Data) {
        print("[Connection #\(connectionId)] Stream \(streamId) - DATA frame, \(payload.count) bytes")
        
        // Check if this is a gRPC message
        if payload.count >= 5 {
            let compressed = payload[0]
            let messageLength = UInt32(payload[1]) << 24 | UInt32(payload[2]) << 16 |
                               UInt32(payload[3]) << 8 | UInt32(payload[4])
            
            print("[Connection #\(connectionId)] gRPC message: compressed=\(compressed), length=\(messageLength)")
            
            if payload.count >= 5 + messageLength {
                let messageData = payload.subdata(in: 5..<5+Int(messageLength))
                print("[Connection #\(connectionId)] Message hex: \(messageData.prefix(100).hexEncodedString())")
                
                // Send a response
                sendGRPCResponse(socket: socket, connectionId: connectionId, streamId: streamId)
            }
        }
    }
    
    private func sendGRPCResponse(socket: Int32, connectionId: Int, streamId: UInt32) {
        print("[Connection #\(connectionId)] Sending response for stream \(streamId)")
        
        // Send HEADERS frame with :status = 200
        let headersData = Data([0x88]) // :status = 200 (indexed)
        let headersFrame = createHTTP2Frame(type: 0x01, flags: 0x04, streamId: streamId, payload: headersData)
        _ = headersFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, headersFrame.count, 0)
        }
        
        // Create GetValue response (not found)
        var response = Data()
        response.append(0x08) // field 1, wire type 0
        response.append(0x00) // found = false
        
        // Wrap in gRPC message
        var grpcMessage = Data()
        grpcMessage.append(0x00) // not compressed
        var length = UInt32(response.count).bigEndian
        grpcMessage.append(Data(bytes: &length, count: 4))
        grpcMessage.append(response)
        
        // Send DATA frame with END_STREAM
        let dataFrame = createHTTP2Frame(type: 0x00, flags: 0x01, streamId: streamId, payload: grpcMessage)
        _ = dataFrame.withUnsafeBytes { bytes in
            send(socket, bytes.baseAddress, dataFrame.count, 0)
        }
        
        print("[Connection #\(connectionId)] Response sent for stream \(streamId)")
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