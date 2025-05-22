import Testing
import FileSystemTesting
import FileSystem
import Path

@discardableResult
public func createFiles(_ files: [String], content: String? = nil) async throws -> [AbsolutePath] {
    let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
    let fileSystem = FileSystem()
    let paths = try files.map { temporaryPath.appending(try RelativePath(validating: $0)) }

    for item in paths {
        if try await !fileSystem.exists(item.parentDirectory, isDirectory: true) {
            try await fileSystem.makeDirectory(at: item.parentDirectory)
        }
        if try await fileSystem.exists(item) {
            try await fileSystem.remove(item)
        }
        if let content {
            try await fileSystem.writeText(content, at: item)
        } else {
            try await fileSystem.touch(item)
        }
    }
    return paths
}
