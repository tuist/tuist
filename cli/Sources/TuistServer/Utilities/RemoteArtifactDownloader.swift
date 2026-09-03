import FileSystem
import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Mockable
import Path
import TuistHTTP
import TuistLogging

/// How much of an artifact has arrived so far.
public struct RemoteArtifactDownloadProgress: Sendable, Equatable {
    public let downloadedBytes: Int64
    public let totalBytes: Int64

    public init(downloadedBytes: Int64, totalBytes: Int64) {
        self.downloadedBytes = downloadedBytes
        self.totalBytes = totalBytes
    }

    public var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(1, Double(downloadedBytes) / Double(totalBytes))
    }
}

public typealias ArtifactDownloadProgressContinuation = AsyncStream<RemoteArtifactDownloadProgress>.Continuation

enum RemoteArtifactDownloaderError: LocalizedError, Equatable {
    case urlSessionError(url: URL, httpMethod: String, description: String)
    case noURLResponse(URL?)
    case unsatisfiableRange(url: URL, offset: Int64)

    var errorDescription: String? {
        switch self {
        case let .urlSessionError(url, httpMethod, error):
            return "Received a session error when sending \(httpMethod) request to \(url.absoluteString): \(error)"
        case let .noURLResponse(url):
            if let url {
                return "The response from request to URL \(url.absoluteString) doesnt' have the expected type HTTPURLResponse"
            } else {
                return "Received a response that doesn't have the expected type HTTPURLResponse"
            }
        case let .unsatisfiableRange(url, offset):
            return "The server did not serve the artifact at \(url.absoluteString) from byte \(offset)."
        }
    }
}

struct RemoteArtifactDownloadStatusCodeError: HTTPStatusCodeError, LocalizedError, Equatable {
    let url: URL
    let httpStatusCode: Int

    var errorDescription: String? {
        "Received status code \(httpStatusCode) when downloading the artifact at \(url.absoluteString)."
    }
}

@Mockable
public protocol RemoteArtifactDownloading {
    /// Returns a temporary file the caller owns and is expected to remove.
    func download(url: URL, progress: ArtifactDownloadProgressContinuation?) async throws -> AbsolutePath?
}

extension RemoteArtifactDownloading {
    public func download(url: URL) async throws -> AbsolutePath? {
        try await download(url: url, progress: nil)
    }
}

public struct RemoteArtifactDownloader: RemoteArtifactDownloading {
    private let urlSession: URLSession
    private let retryProvider: RetryProviding
    private let fileSystem: FileSysteming
    private let chunkByteCount: Int64
    private let downloadsDirectory: AbsolutePath?

    public init() {
        self.init(urlSession: .tuistLargeTransfer)
    }

    init(
        urlSession: URLSession,
        retryProvider: RetryProviding = RetryProvider(),
        fileSystem: FileSysteming = FileSystem(),
        chunkByteCount: Int64 = 16 * 1024 * 1024,
        downloadsDirectory: AbsolutePath? = nil
    ) {
        self.urlSession = urlSession
        self.retryProvider = retryProvider
        self.fileSystem = fileSystem
        self.chunkByteCount = chunkByteCount
        self.downloadsDirectory = downloadsDirectory
    }

    public func download(
        url: URL,
        progress: ArtifactDownloadProgressContinuation?
    ) async throws -> AbsolutePath? {
        defer { progress?.finish() }

        let destination = try makeDestination(for: url)
        try await fileSystem.touch(destination)

        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(atPath: destination.pathString) } }

        var offset: Int64 = 0
        var total: Int64?
        var validator: String?

        while true {
            let requestedOffset = offset
            let requestedValidator = validator
            let chunk = try await retryProvider.runWithRetries {
                try await fetch(url: url, from: requestedOffset, validator: requestedValidator)
            }

            switch chunk {
            case .notFound:
                return nil
            case let .whole(localURL, byteCount, eTag):
                try await replace(destination, with: localURL)
                offset = byteCount
                total = byteCount
                validator = eTag
            case let .partial(localURL, contentRange, eTag):
                guard contentRange.start == requestedOffset, contentRange.byteCount > 0 else {
                    throw RemoteArtifactDownloaderError.unsatisfiableRange(url: url, offset: requestedOffset)
                }
                try await append(localURL, to: destination)
                offset += contentRange.byteCount
                total = contentRange.total
                validator = validator ?? eTag
            }

            guard let totalBytes = total else { break }
            progress?.yield(RemoteArtifactDownloadProgress(downloadedBytes: offset, totalBytes: totalBytes))
            if offset >= totalBytes { break }
        }

        completed = true
        return destination
    }

    // MARK: - Private

    private enum FetchedChunk {
        case notFound
        case whole(localURL: URL, byteCount: Int64, eTag: String?)
        case partial(localURL: URL, contentRange: ContentRange, eTag: String?)
    }

    private func fetch(url: URL, from offset: Int64, validator: String?) async throws -> FetchedChunk {
        var request = URLRequest(url: url)
        request.setValue("bytes=\(offset)-\(offset + chunkByteCount - 1)", forHTTPHeaderField: "Range")
        if let validator {
            request.setValue(validator, forHTTPHeaderField: "If-Range")
        }

        let localURL: URL
        let response: URLResponse
        do {
            (localURL, response) = try await urlSession.download(for: request)
        } catch {
            throw RemoteArtifactDownloaderError.urlSessionError(
                url: url,
                httpMethod: request.httpMethod ?? "GET",
                description: error.localizedDescription
            )
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RemoteArtifactDownloaderError.noURLResponse(url)
        }
        let eTag = httpResponse.value(forHTTPHeaderField: "ETag")

        switch httpResponse.statusCode {
        case 404:
            return .notFound
        case 206:
            guard let contentRange = ContentRange(httpResponse.value(forHTTPHeaderField: "Content-Range")) else {
                throw RemoteArtifactDownloaderError.unsatisfiableRange(url: url, offset: offset)
            }
            if offset > 0 {
                Logger.current.debug("Resuming the download of \(url.absoluteString) from byte \(offset).")
            }
            return .partial(localURL: localURL, contentRange: contentRange, eTag: eTag)
        case 200 ..< 300:
            let byteCount = try await fileSystem.fileMetadata(at: try AbsolutePath(validating: localURL.path))?.size ?? 0
            return .whole(localURL: localURL, byteCount: byteCount, eTag: eTag)
        default:
            throw RemoteArtifactDownloadStatusCodeError(url: url, httpStatusCode: httpResponse.statusCode)
        }
    }

    private func append(_ source: URL, to destination: AbsolutePath) async throws {
        let data = try Data(contentsOf: source)
        let handle = try FileHandle(forWritingTo: destination.url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
        try? FileManager.default.removeItem(at: source)
    }

    private func replace(_ destination: AbsolutePath, with source: URL) async throws {
        if try await fileSystem.exists(destination) {
            try await fileSystem.remove(destination)
        }
        try await fileSystem.move(from: try AbsolutePath(validating: source.path), to: destination)
    }

    private func makeDestination(for url: URL) throws -> AbsolutePath {
        let directory = try downloadsDirectory ?? AbsolutePath(validating: NSTemporaryDirectory())
        let component = url.lastPathComponent
        return directory.appending(component: "\(UUID().uuidString)-\(component.isEmpty ? "artifact" : component)")
    }
}

struct ContentRange: Equatable {
    let start: Int64
    let end: Int64
    let total: Int64

    var byteCount: Int64 { end - start + 1 }

    init?(_ value: String?) {
        guard let value else { return nil }
        let specification = value.trimmingCharacters(in: .whitespaces)
        guard specification.hasPrefix("bytes ") else { return nil }
        let components = specification.dropFirst("bytes ".count).split(separator: "/")
        guard components.count == 2, let total = Int64(components[1]) else { return nil }
        let bounds = components[0].split(separator: "-")
        guard bounds.count == 2,
              let start = Int64(bounds[0]),
              let end = Int64(bounds[1]),
              start <= end
        else { return nil }
        self.start = start
        self.end = end
        self.total = total
    }
}
