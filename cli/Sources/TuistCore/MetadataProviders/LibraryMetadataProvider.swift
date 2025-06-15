import FileSystem
import Foundation
import Path
import TuistSupport
import XcodeGraph

// MARK: - Provider Errors

enum LibraryMetadataProviderError: FatalError, Equatable {
    case libraryNotFound(AbsolutePath)
    case publicHeadersNotFound(libraryPath: AbsolutePath, headersPath: AbsolutePath)
    case swiftModuleMapNotFound(libraryPath: AbsolutePath, moduleMapPath: AbsolutePath)

    // MARK: - FatalError

    var description: String {
        switch self {
        case let .libraryNotFound(path):
            return "Couldn't find library at \(path.pathString)"
        case let .publicHeadersNotFound(libraryPath: libraryPath, headersPath: headersPath):
            return "Couldn't find the public headers at \(headersPath.pathString) for library \(libraryPath.pathString)"
        case let .swiftModuleMapNotFound(libraryPath: libraryPath, moduleMapPath: moduleMapPath):
            return "Couldn't find the public headers at \(moduleMapPath.pathString) for library \(libraryPath.pathString)"
        }
    }

    var type: ErrorType {
        switch self {
        case .libraryNotFound, .publicHeadersNotFound, .swiftModuleMapNotFound:
            return .abort
        }
    }
}

// MARK: - Provider

public protocol LibraryMetadataProviding: PrecompiledMetadataProviding {
    /// Loads all the metadata associated with a library (.a / .dylib) at the specified path
    /// - Note: This performs various shell calls and disk operations
    func loadMetadata(
        at path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?
    ) async throws -> LibraryMetadata
}

// MARK: - Default Implementation

public final class LibraryMetadataProvider: PrecompiledMetadataProvider, LibraryMetadataProviding {
    private let fileSystem: FileSysteming

    init(
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.fileSystem = fileSystem
    }

    public func loadMetadata(
        at path: AbsolutePath,
        publicHeaders: AbsolutePath,
        swiftModuleMap: AbsolutePath?
    ) async throws -> LibraryMetadata {
        guard try await fileSystem.exists(path) else {
            throw LibraryMetadataProviderError.libraryNotFound(path)
        }
        guard try await fileSystem.exists(publicHeaders) else {
            throw LibraryMetadataProviderError.publicHeadersNotFound(libraryPath: path, headersPath: publicHeaders)
        }
        if let swiftModuleMap {
            guard try await fileSystem.exists(swiftModuleMap) else {
                throw LibraryMetadataProviderError.swiftModuleMapNotFound(libraryPath: path, moduleMapPath: swiftModuleMap)
            }
        }

        let architectures = try architectures(binaryPath: path)
        let linking = try linking(binaryPath: path)
        return LibraryMetadata(
            path: path,
            publicHeaders: publicHeaders,
            swiftModuleMap: swiftModuleMap,
            architectures: architectures,
            linking: linking
        )
    }
}

#if DEBUG
    public final class MockLibraryMetadataProvider: MockPrecompiledMetadataProvider, LibraryMetadataProviding {
        public var loadMetadataStub: ((AbsolutePath, AbsolutePath, AbsolutePath?) throws -> LibraryMetadata)?
        public func loadMetadata(
            at path: AbsolutePath,
            publicHeaders: AbsolutePath,
            swiftModuleMap: AbsolutePath?
        ) throws -> LibraryMetadata {
            if let stub = loadMetadataStub {
                return try stub(path, publicHeaders, swiftModuleMap)
            } else {
                return LibraryMetadata.test(
                    path: path,
                    publicHeaders: publicHeaders,
                    swiftModuleMap: swiftModuleMap
                )
            }
        }
    }
#endif
