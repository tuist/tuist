import Darwin
import FileSystem
import FileSystemTesting
import Foundation
import Path
import Testing

@testable import TuistSupport

struct CacheSocketServiceTests {
    private let fileSystem = FileSystem()
    private let subject = CacheSocketService()

    @Test(.inTemporaryDirectory)
    func waitUntilListening_returnsTrueForAListeningSocket() async throws {
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
            await subject.waitUntilListening(
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

    /// A socket file left behind by a process that exited is not a reachable peer:
    /// `connect()` answers `ECONNREFUSED` where an existence check reports healthy.
    @Test(.inTemporaryDirectory)
    func canConnect_returnsFalseForAStaleSocketFile() async throws {
        let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
        let shortDirectoryPath = try AbsolutePath(validating: "/tmp/\(UUID().uuidString)")
        try await fileSystem.createSymbolicLink(from: shortDirectoryPath, to: temporaryDirectory)
        let socketPath = shortDirectoryPath.appending(component: "stale.sock")
        defer {
            unlink(socketPath.pathString)
            unlink(shortDirectoryPath.pathString)
        }
        try bindAndClose(at: socketPath)
        try #require(await fileSystem.exists(socketPath))

        #expect(subject.canConnect(to: socketPath) == false)
    }

    /// Binds a listening socket and closes it, leaving the socket file on disk the
    /// way the CAS proxy does when it exits.
    private func bindAndClose(at socketPath: AbsolutePath) throws {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        try #require(descriptor >= 0)
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
                Darwin.bind(descriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        try #require(bindResult == 0)
        try #require(Darwin.listen(descriptor, 1) == 0)
        close(descriptor)
    }
}
