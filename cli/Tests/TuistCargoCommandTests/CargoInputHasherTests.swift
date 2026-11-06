import FileSystem
import FileSystemTesting
import Foundation
import Testing
import TuistREAPI
@testable import TuistCargoCommand

struct CargoInputHasherTests {
    @Test(.inTemporaryDirectory) func reusesUnchangedInputsWithinOneInvocation() throws {
        let file = try input()
        var reads = 0
        let hasher = CargoInputHasher { file in
            reads += 1
            return try REAPI.digest(file: file)
        }
        let digest = try hasher.digest(file)
        #expect(try hasher.digest(file) == digest)
        #expect(reads == 1)
        #expect(try CargoInputHasher().digest(file) == digest)
    }

    @Test(.inTemporaryDirectory, arguments: [false, true])
    func sharesOnlyUnchangedToolchainInputsWithinTheSession(batch: Bool) throws {
        let file = try input()
        let session = file.deletingLastPathComponent().appendingPathComponent("session")
        var reads = 0
        let hash: (URL) throws -> REAPI.Digest = { file in
            reads += 1
            return try REAPI.digest(file: file)
        }
        func digest(_ hasher: CargoInputHasher) throws -> REAPI.Digest {
            if batch {
                return try hasher.withSharedDigests(under: file.deletingLastPathComponent()) {
                    try hasher.digest(file, shared: true)
                }
            }
            return try hasher.digest(file, shared: true)
        }
        let original = try digest(CargoInputHasher(sessionDirectory: session, hashFile: hash))
        #expect(try digest(CargoInputHasher(sessionDirectory: session, hashFile: hash)) == original)
        #expect(reads == 1)
        #expect(try CargoInputHasher(sessionDirectory: session, hashFile: hash).digest(file) == original)
        #expect(reads == 2)
        let other = session.appendingPathComponent("another-session")
        #expect(try digest(CargoInputHasher(sessionDirectory: other, hashFile: hash)) == original)
        #expect(reads == 3)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let modified = try #require(attributes[.modificationDate])
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("next".utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        let changed = try digest(CargoInputHasher(sessionDirectory: session, hashFile: hash))
        #expect(changed == REAPI.digest(Data("next".utf8)))
        #expect(changed != original)
        #expect(reads == 4)
    }

    @Test(.inTemporaryDirectory) func sharedDigestsDoNotCacheDirectoryDiscovery() throws {
        let file = try input()
        let root = file.deletingLastPathComponent()
        let session = root.appendingPathComponent("session")
        func snapshot() throws -> [REAPI.Digest] {
            let hasher = CargoInputHasher(sessionDirectory: session)
            return try hasher.withSharedDigests(under: root) {
                try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
                    .filter { $0.lastPathComponent != "session" }.sorted { $0.path < $1.path }
                    .map { try hasher.digest($0, shared: true) }
            }
        }
        #expect(try snapshot() == [REAPI.digest(Data("data".utf8))])
        let extra = root.appendingPathComponent("new-library")
        try Data("added".utf8).write(to: extra)
        #expect(try snapshot() == [REAPI.digest(Data("data".utf8)), REAPI.digest(Data("added".utf8))])
        try FileManager.default.removeItem(at: file)
        #expect(try snapshot() == [REAPI.digest(Data("added".utf8))])
    }

    @Test(.inTemporaryDirectory) func invalidatesChangedContentWithRestoredModificationTime() throws {
        let file = try input()
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        let modified = try #require(attributes[.modificationDate])
        let hasher = CargoInputHasher()
        let original = try hasher.digest(file)
        let handle = try FileHandle(forWritingTo: file)
        try handle.write(contentsOf: Data("next".utf8))
        try handle.close()
        try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: file.path)
        #expect(try hasher.digest(file) != original)
        #expect(try hasher.digest(file) == REAPI.digest(Data("next".utf8)))
    }

    @Test(.inTemporaryDirectory) func rehashesInputsWithCoarseTimestamps() throws {
        let file = try input()
        var reads = 0
        let hasher = CargoInputHasher(
            sessionDirectory: file.deletingLastPathComponent(),
            identify: { _ in .init(fields: [], precise: false) }
        ) { file in
            reads += 1
            return try REAPI.digest(file: file)
        }
        _ = try hasher.digest(file, shared: true)
        _ = try hasher.digest(file, shared: true)
        #expect(reads == 2)
    }

    @Test(.inTemporaryDirectory) func rejectsMutationsDuringHashing() throws {
        let file = try input()
        let hasher = CargoInputHasher { file in
            let result = try REAPI.digest(file: file)
            try Data("next".utf8).write(to: file)
            return result
        }
        #expect(throws: CargoCacheInvocation.CacheError.self) { try hasher.digest(file) }
    }

    @Test(.inTemporaryDirectory) func reusesSourceAdmissionOnlyForTheSameContent() throws {
        let file = try input()
        let hasher = CargoInputHasher()
        var validations = 0
        let validate: (Data) -> Void = { _ in validations += 1 }
        let original = try hasher.sourceDigest(file, validate: validate)
        #expect(try hasher.sourceDigest(file, validate: validate) == original)
        #expect(validations == 1)
        try Data("next".utf8).write(to: file)
        #expect(try hasher.sourceDigest(file, validate: validate) == REAPI.digest(Data("next".utf8)))
        #expect(validations == 2)
    }

    @Test(.inTemporaryDirectory) func rechecksSourceAdmissionWithCoarseTimestamps() throws {
        let file = try input()
        let hasher = CargoInputHasher(identify: { _ in .init(fields: [], precise: false) })
        let validate: (Data) throws -> Void = { data in
            guard data == Data("data".utf8) else { throw CargoCacheInvocation.CacheError.unsupported }
        }
        _ = try hasher.sourceDigest(file, validate: validate)
        try Data("next".utf8).write(to: file)
        #expect(throws: CargoCacheInvocation.CacheError.self) { try hasher.sourceDigest(file, validate: validate) }
    }

    @Test(.inTemporaryDirectory) func sourceKeysUseTheBytesThatWereActuallyValidated() throws {
        let file = try input()
        let digest = try CargoInputHasher().sourceDigest(file) { data in
            #expect(data == Data("data".utf8))
            try Data("next".utf8).write(to: file)
        }
        #expect(digest == REAPI.digest(Data("data".utf8)))
    }

    @Test(.inTemporaryDirectory) func boundsSourceAdmissionReads() throws {
        let file = try input()
        try Data(repeating: 32, count: 2_000_001).write(to: file)
        #expect(throws: CargoCacheInvocation.CacheError.self) {
            try CargoInputHasher().sourceDigest(file) { _ in Issue.record("Oversized source reached admission") }
        }
    }

    private func input() throws -> URL {
        let root = try #require(FileSystem.temporaryTestDirectory)
        let file = URL(fileURLWithPath: root.pathString).appendingPathComponent("input")
        try Data("data".utf8).write(to: file)
        return file
    }
}
