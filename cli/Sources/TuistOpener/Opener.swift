import FileSystem
import Foundation
import Mockable
import Path
import TuistLogging

enum OpeningError: FatalError, Equatable {
    case notFound(AbsolutePath)

    var type: ErrorType {
        switch self {
        case .notFound:
            return .bug
        }
    }

    var description: String {
        switch self {
        case let .notFound(path):
            return "Couldn't open file at path \(path.pathString)"
        }
    }
}

@Mockable
public protocol Opening: AnyObject {
    func open(path: AbsolutePath, wait: Bool) async throws
    func open(path: AbsolutePath) async throws
    func open(url: URL) throws
    func open(target: String, wait: Bool) throws
    func open(path: AbsolutePath, application: AbsolutePath) throws
    func open(path: AbsolutePath, application: AbsolutePath, wait: Bool) throws
}

public class Opener: Opening {
    private let fileSystem: FileSysteming

    public init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    // MARK: - Opening

    public func open(path: AbsolutePath, wait: Bool) async throws {
        if try await !fileSystem.exists(path) {
            throw OpeningError.notFound(path)
        }
        try open(target: path.pathString, wait: wait)
    }

    public func open(path: AbsolutePath) async throws {
        try await open(path: path, wait: false)
    }

    public func open(url: URL) throws {
        try open(target: url.absoluteString, wait: false)
    }

    public func open(target: String, wait: Bool) throws {
        let process = Process()
        #if os(macOS)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            if wait {
                process.arguments = ["-W", target]
            } else {
                process.arguments = [target]
            }
        #elseif os(Linux)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xdg-open")
            process.arguments = [target]
        #endif
        try process.run()
        if wait {
            process.waitUntilExit()
        }
    }

    public func open(path: AbsolutePath, application: AbsolutePath) throws {
        try open(path: path, application: application, wait: true)
    }

    public func open(path: AbsolutePath, application: AbsolutePath, wait: Bool) throws {
        let process = Process()
        #if os(macOS)
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            var arguments = [path.pathString, "-a", application.pathString]
            if wait {
                arguments.insert("-W", at: 0)
            }
            process.arguments = arguments
        #elseif os(Linux)
            // On Linux, run the application directly with the file as argument
            process.executableURL = URL(fileURLWithPath: application.pathString)
            process.arguments = [path.pathString]
        #endif
        try process.run()
        if wait {
            process.waitUntilExit()
        }
    }
}
