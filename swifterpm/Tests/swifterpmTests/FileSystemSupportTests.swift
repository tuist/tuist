import FileSystem
import Foundation
import Path
import Testing
@testable import SwifterPMCore

struct FileSystemSupportTests {
    @Test
    func readsWritesListsAndRemovesFiles() async throws {
        try await withTemporaryDirectory { root in
            let file = root.appendingPathComponent("nested/file.txt")
            try await fileSystem.write(Data("hello".utf8), to: file)

            #expect(try await fileSystem.exists(file.absolutePath))
            #expect(try await fileSystem.exists(file.absolutePath, isDirectory: false))
            #expect(
                String(data: try await fileSystem.readFile(at: file.absolutePath), encoding: .utf8)
                    == "hello"
            )
            #expect(try await fileSystem.fileMetadata(at: file.absolutePath) != nil)

            let entries = try await fileSystem.contentsOfDirectory(at: file.deletingLastPathComponent())
            #expect(Set(entries.map(\.lastPathComponent)) == ["file.txt"])

            try await fileSystem.remove(file.absolutePath)
            #expect(!(try await fileSystem.exists(file.absolutePath)))
        }
    }

    @Test
    func makeDirectoryWithIntermediatesIsRaceSafeAcrossConcurrentTasks() async throws {
        try await withTemporaryDirectory { root in
            let shared = root.appendingPathComponent("a/b/c/d")
            try await withThrowingTaskGroup(of: Void.self) { group in
                for index in 0..<32 {
                    let target = shared.appendingPathComponent("leaf-\(index)")
                    group.addTask {
                        try await fileSystem.makeDirectory(
                            at: target.deletingLastPathComponent().absolutePath,
                            options: [.createTargetParentDirectories]
                        )
                    }
                }
                try await group.waitForAll()
            }
            #expect(try await fileSystem.exists(shared.absolutePath, isDirectory: true))
        }
    }

    @Test
    func createsSymlinksAndReportsCurrentDirectory() async throws {
        try await withTemporaryDirectory { root in
            let target = root.appendingPathComponent("target.txt")
            let link = root.appendingPathComponent("link.txt")
            let targetDirectory = root.appendingPathComponent("target-directory")
            let directoryLink = root.appendingPathComponent("directory-link")
            try await fileSystem.write(Data("target".utf8), to: target)
            try await fileSystem.makeDirectory(
                at: targetDirectory.absolutePath, options: [.createTargetParentDirectories])
            try await fileSystem.createSymbolicLink(
                from: link.absolutePath, to: target.absolutePath)
            try await fileSystem.createSymbolicLink(
                from: directoryLink.absolutePath, to: targetDirectory.absolutePath)

            #expect(try await fileSystem.exists(link.absolutePath))
            #expect(!(fileSystem.isDirectoryAndNotSymlink(link)))
            #expect(try await fileSystem.exists(directoryLink.absolutePath, isDirectory: true))
            #expect(!(fileSystem.isDirectoryAndNotSymlink(directoryLink)))
            #expect(!(try await fileSystem.currentWorkingDirectory().pathString.isEmpty))
        }
    }
}
