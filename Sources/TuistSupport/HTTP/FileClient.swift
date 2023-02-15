import Foundation
import TSCBasic

enum FileClientError: LocalizedError, FatalError {
    case urlSessionError(URLRequest, Error, AbsolutePath?)
    case serverSideError(URLRequest, HTTPURLResponse, AbsolutePath?)
    case invalidResponse(URLRequest, AbsolutePath?)
    case noLocalURL(URLRequest)

    // MARK: - FatalError

    public var description: String {
        switch self {
        case let .urlSessionError(request, error, path):
            return "Received a session error\(pathSubstring(path)) when performing \(request.descriptionForError): \(error.localizedDescription)"
        case let .invalidResponse(request, path):
            return "Received unexpected response from the network when performing \(request.descriptionForError)\(pathSubstring(path))"
        case let .serverSideError(request, response, path):
            return "Received error \(response.statusCode) when performing \(request.descriptionForError)\(pathSubstring(path))"
        case let .noLocalURL(request):
            return "Could not locate on disk the downloaded file after performing \(request.descriptionForError)"
        }
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
                return try AbsolutePath(validating: localUrl.path)
            } else {
                throw FileClientError.invalidResponse(request, nil)
            }
        } catch {
            if error is FileClientError {
                throw error
            } else {
                throw FileClientError.urlSessionError(request, error, nil)
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
                throw FileClientError.urlSessionError(request, error, file)
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
