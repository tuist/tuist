import Darwin
import FileSystem
import FileSystemTesting
import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2
import Path
import Testing

@testable import TuistKit

struct CacheSocketServiceTests {
    private let fileSystem = FileSystem()
    private let subject = CacheSocketService()

    @Test(.inTemporaryDirectory)
    func waitUntilListening_doesNotCrashGRPCServer() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let shortDirectoryPath = try AbsolutePath(validating: "/tmp/\(UUID().uuidString)")
        try await fileSystem.createSymbolicLink(from: shortDirectoryPath, to: temporaryDirectory)
        let socketPath = shortDirectoryPath.appending(component: "cache.sock")
        defer { unlink(shortDirectoryPath.pathString) }
        let server = GRPCServer(
            transport: .http2NIOPosix(
                address: .unixDomainSocket(path: socketPath.pathString),
                transportSecurity: .plaintext
            ),
            services: []
        )

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await server.serve() }
            defer { server.beginGracefulShutdown() }

            for _ in 0 ..< 10 {
                #expect(await subject.waitUntilListening(at: socketPath, timeout: .seconds(5)))
            }
        }
    }

    @Test(.inTemporaryDirectory)
    func waitUntilListening_returnsFalseWhenServerDoesNotAccept() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let shortDirectoryPath = try AbsolutePath(validating: "/tmp/\(UUID().uuidString)")
        try await fileSystem.createSymbolicLink(from: shortDirectoryPath, to: temporaryDirectory)
        let socketPath = shortDirectoryPath.appending(component: "cache.sock")
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
        defer {
            close(descriptor)
            unlink(socketPath.pathString)
            unlink(shortDirectoryPath.pathString)
        }

        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        try #require(socketPath.pathString.utf8.count < MemoryLayout.size(ofValue: address.sun_path))
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
            buffer.copyBytes(from: socketPath.pathString.utf8)
        }

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.bind(
                    descriptor,
                    socketAddress,
                    socklen_t(MemoryLayout<sockaddr_un>.size)
                )
            }
        }
        try #require(bindResult == 0)
        try #require(Darwin.listen(descriptor, 1) == 0)

        #expect(
            await !subject.waitUntilListening(
                at: socketPath,
                timeout: .milliseconds(100)
            )
        )
    }

    @Test(.inTemporaryDirectory)
    func waitUntilListening_returnsFalseWhenNothingIsListening() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let socketPath = temporaryDirectory.appending(component: "missing.sock")

        #expect(
            await !subject.waitUntilListening(
                at: socketPath,
                timeout: .zero
            )
        )
    }
}
