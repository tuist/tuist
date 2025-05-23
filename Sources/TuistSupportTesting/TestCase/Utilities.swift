import FileSystem
import FileSystemTesting
import Path
import Testing

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

@discardableResult
public func makeDirectories(_ folders: [String]) async throws -> [AbsolutePath] {
    let temporaryPath = try #require(FileSystem.temporaryTestDirectory)
    let fileSystem = FileSystem()
    let paths = try folders.map { temporaryPath.appending(try RelativePath(validating: $0)) }
    for path in paths {
        try await fileSystem.makeDirectory(at: path)
    }
    return paths
}
