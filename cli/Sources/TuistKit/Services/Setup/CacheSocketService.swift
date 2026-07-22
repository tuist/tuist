#if canImport(Darwin)
    import Darwin
#elseif canImport(Glibc)
    import Glibc
#endif
import Foundation
import Mockable
import Path

@Mockable
protocol CacheSocketServicing {
    func waitUntilListening(at path: AbsolutePath, timeout: Duration) async -> Bool
}

struct CacheSocketService: CacheSocketServicing {
    func waitUntilListening(at path: AbsolutePath, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        repeat {
            if canConnect(to: path.pathString) {
                return true
            }
            if clock.now >= deadline || Task.isCancelled {
                return false
            }
            try? await Task.sleep(for: .milliseconds(100))
        } while true
    }

    private func canConnect(to path: String) -> Bool {
        #if canImport(Darwin)
            let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        #else
            let descriptor = Glibc.socket(AF_UNIX, Int32(SOCK_STREAM.rawValue), 0)
        #endif
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var address = sockaddr_un()
        #if canImport(Darwin)
            address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        #endif
        address.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = Array(path.utf8)
        guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
            return false
        }

        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: pathBytes)
        }

        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                #if canImport(Darwin)
                    Darwin.connect(
                        descriptor,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                #else
                    Glibc.connect(
                        descriptor,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_un>.size)
                    )
                #endif
            }
        }
        return result == 0
    }
}
