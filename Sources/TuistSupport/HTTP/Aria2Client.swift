import Combine
import Foundation
import TSCBasic

public class Aria2Client: FileClienting {
    // MARK: - Attributes

    /// Fallback `FileClienting` implementation to provide functionalities aria2 does not support.
    private let fileClient: FileClienting

    // MARK: - Init

    public init(fileClient: FileClienting = FileClient()) {
        self.fileClient = fileClient
    }

    // MARK: - Public

    public func download(url: URL) async throws -> AbsolutePath {
        let request = URLRequest(url: url)
        let localUrl = try await downloadWithAria2(for: request)
        return AbsolutePath(localUrl.path)
    }

    public func upload(file: AbsolutePath, hash: String, to url: URL) async throws -> Bool {
        try await fileClient.upload(file: file, hash: hash, to: url)
    }

    // MARK: - Private

    private func aria2Path() throws -> String {
        try System.shared.which("aria2c")
    }

    private func downloadWithAria2(for request: URLRequest) async throws -> URL {
        guard let url = request.url else {
            throw FileClientError.invalidResponse(request, nil)
        }

        // Random filename to avoid name collisions
        let filename = url.lastPathComponent.appending("-\(UUID().uuidString)")
        let storePath = AbsolutePath(FileManager.default.temporaryDirectory.appendingPathComponent(filename).path)

        var command = [try aria2Path()]

        // Maximum number of connections to one server for each download.
        command.append("--max-connection-per-server=16")

        // Download the file using 16 connections.
        command.append("--split=16")

        // Interval in seconds to output download progress summary.
        command.append("--summary-interval=0")

        // Stop application when process is not running
        command.append("--stop-with-process=\(ProcessInfo.processInfo.processIdentifier)")

        // Directory to store the downloaded file.
        command.append("--dir=\(storePath.parentDirectory.pathString)")

        // File name of the downloaded file
        command.append("--out=\(storePath.basename)")

        // URI to download
        command.append(url.absoluteString)

        return try await withCheckedThrowingContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = System.shared.publisher(command)
                .mapToString()
                .collectAndMergeOutput()
                .sink { result in
                    switch result {
                    case .finished:
                        break
                    case let .failure(error):
                        continuation.resume(throwing: error)
                    }
                    cancellable?.cancel()
                } receiveValue: { _ in
                    continuation.resume(with: .success(storePath.url))
                }
        }
    }
}
