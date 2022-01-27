import Foundation
import TSCBasic

enum FileClientError: LocalizedError, FatalError {
    case urlSessionError(Error, AbsolutePath?)
    case serverSideError(URLRequest, HTTPURLResponse, AbsolutePath?)
    case invalidResponse(URLRequest, AbsolutePath?)
    case noLocalURL(URLRequest)

    // MARK: - FatalError

    public var description: String {
        var output: String

        switch self {
        case let .urlSessionError(error, path):
            output = "Received a session error"
            output.append(pathSubstring(path))
            if let error = error as? LocalizedError {
                output.append(": \(error.localizedDescription)")
            }
        case let .invalidResponse(urlRequest, path):
            output = "Received unexpected response from the network with \(urlRequest.descriptionForError)"
            output.append(pathSubstring(path))
        case let .serverSideError(request, response, path):
            output =
                "Got error code: \(response.statusCode) returned by the server after performing \(request.descriptionForError)"
            output.append(pathSubstring(path))
        case let .noLocalURL(request):
            output = "Could not locate file on disk the downloaded file after performing \(request.descriptionForError)"
        }

        return output
    }

    var type: ErrorType {
        switch self {
        case .urlSessionError: return .bug
        case .serverSideError: return .bug
        case .invalidResponse: return .bug
        case .noLocalURL: return .bug
        }
    }

    private func pathSubstring(_ path: AbsolutePath?) -> String {
        guard let path = path else { return "" }
        return " for file at path \(path.pathString)"
    }

    // MARK: - LocalizedError

    public var errorDescription: String? { description }
}

public protocol FileClienting {
    func upload(file: AbsolutePath, hash: String, to url: URL) async throws -> Bool
    func download(url: URL) async throws -> AbsolutePath
}

public class FileClient: FileClienting {
    // MARK: - Attributes

    let session: URLSession
    private let successStatusCodeRange = 200 ..< 300

    // MARK: - Init

    public init(session: URLSession = URLSession.shared) {
        self.session = session
    }

    // MARK: - Public

    public func download(url: URL) async throws -> AbsolutePath {
        let request = URLRequest(url: url)
        do {
            let (localUrl, response) = try await session.download(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw FileClientError.invalidResponse(request, nil)
            }
            if successStatusCodeRange.contains(response.statusCode) {
                return AbsolutePath(localUrl.path)
            } else {
                throw FileClientError.invalidResponse(request, nil)
            }
        } catch {
            if error is FileClientError {
                throw error
            } else {
                throw FileClientError.urlSessionError(error, nil)
            }
        }
    }

    public func upload(file: AbsolutePath, hash _: String, to url: URL) async throws -> Bool {
        let fileSize = try FileHandler.shared.fileSize(path: file)
        let fileData = try Data(contentsOf: file.url)
        let request = uploadRequest(url: url, fileSize: fileSize, data: fileData)
        do {
            let (_, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw FileClientError.invalidResponse(request, file)
            }
            if successStatusCodeRange.contains(response.statusCode) {
                return true
            } else {
                throw FileClientError.serverSideError(request, response, file)
            }
        } catch {
            if error is FileClientError {
                throw error
            } else {
                throw FileClientError.urlSessionError(error, file)
            }
        }
    }

    // MARK: - Private

    private func uploadRequest(url: URL, fileSize: UInt64, data: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        request.setValue("zip", forHTTPHeaderField: "Content-Encoding")
        request.httpBody = data
        return request
    }
}

extension URLSession {
    /// Convenience method to load data using an URLRequest, creates and resumes an URLSessionDataTask internally.
    ///
    /// - Parameter request: The URLRequest for which to load data.
    /// - Returns: Data and response.
    @available(macOS, deprecated: 12.0, message: "This extension is no longer necessary.")
    public func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.dataTask(with: request) { data, response, error in
                guard let data = data, let response = response else {
                    let error = error ?? URLError(.badServerResponse)
                    return continuation.resume(throwing: error)
                }

                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    /// Convenience method to download using an URLRequest, creates and resumes an URLSessionDownloadTask internally.
    ///
    /// - Parameter request: The URLRequest for which to download.
    /// - Returns: Downloaded file URL and response. The file will not be removed automatically.
    @available(macOS, deprecated: 12.0, message: "This extension is no longer necessary.")
    public func download(for request: URLRequest, delegate _: URLSessionTaskDelegate? = nil) async throws -> (URL, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = self.downloadTask(with: request) { url, response, responseError in
                guard let url = url, let response = response else {
                    let error = responseError ?? URLError(.badServerResponse)
                    return continuation.resume(throwing: error)
                }
                do {
                    let storedPath = AbsolutePath(url.path.appending("-Temp"))
                    // File needs to be moved, otherwise it will deleted when the closure completes
                    try FileHandler.shared.move(from: AbsolutePath(url.path), to: storedPath)
                    continuation.resume(returning: (storedPath.url, response))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
            task.resume()
        }
    }
}
