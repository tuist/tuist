import Foundation
import RxSwift
import TSCBasic
import TuistSupport

enum FileClientError: LocalizedError, FatalError {
    case urlSessionError(Error, AbsolutePath?)
    case serverSideError(HTTPURLResponse, AbsolutePath?)
    case invalidResponse(URLRequest, AbsolutePath?)
    case noLocalURL(HTTPURLResponse)

    // MARK: - FatalError

    public var description: String {
        var output: String

        switch self {
        case let .urlSessionError(error, path):
            output = "Received a session error"
            if let path = path {
                output.append(" while uploading file at path \(path.pathString)")
            }
            if let error = error as? LocalizedError {
                output.append("\nError: \(error.localizedDescription)")
            }
        case let .invalidResponse(urlRequest, path):
            output = "Received unexpected response from the network with url request \(urlRequest)"
            if let path = path {
                output.append(" while uploading file at path \(path.pathString)")
            }
        case let .serverSideError(response, path):
            output = "Got error code: \(response.statusCode) returned by the server"
            if let path = path {
                output.append(" when uploading file at path \(path.pathString)")
            }
            output.append("HTTPURLResponse: \(response.description)")
        case let .noLocalURL(response):
            output = "Could not locate file on disk the downloaded file. HTTPURLResponse: \(response.description)"
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

    // MARK: - LocalizedError

    public var errorDescription: String? { description }
}

public protocol FileClienting {
    func upload(file: AbsolutePath, hash: String, to url: URL) -> Single<Bool>
    func download(url: URL) -> Single<AbsolutePath>
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

    public func download(url: URL) -> Single<AbsolutePath> {
        dispatchDownload(request: URLRequest(url: url)).map { AbsolutePath($0.path) }
    }

    public func upload(file: AbsolutePath, hash _: String, to url: URL) -> Single<Bool> {
        Single<Bool>.create { observer -> Disposable in
            do {
                let fileSize = try FileHandler.shared.fileSize(path: file)
                let fileData = try Data(contentsOf: file.url)

                let request = self.uploadRequest(url: url, fileSize: fileSize, data: fileData)
                let uploadTask = self.session.dataTask(with: request) { _, response, error in
                    if let error = error {
                        observer(.error(FileClientError.urlSessionError(error, file)))
                    } else if let response = response as? HTTPURLResponse {
                        if self.successStatusCodeRange.contains(response.statusCode) {
                            observer(.success(true))
                        } else {
                            observer(.error(FileClientError.serverSideError(response, file)))
                        }
                    } else {
                        observer(.error(FileClientError.invalidResponse(request, file)))
                    }
                }
                uploadTask.resume()
                return Disposables.create { uploadTask.cancel() }
            } catch {
                observer(.error(error))
            }
            return Disposables.create {}
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

    private func dispatchDownload(request: URLRequest) -> Single<URL> {
        Single.create { observer in
            let task = self.session.downloadTask(with: request) { localURL, response, networkError in
                if let networkError = networkError {
                    observer(.error(FileClientError.urlSessionError(networkError, nil)))
                } else if let response = response as? HTTPURLResponse {
                    guard let localURL = localURL else {
                        observer(.error(FileClientError.noLocalURL(response)))
                        return
                    }

                    if self.successStatusCodeRange.contains(response.statusCode) {
                        observer(.success(localURL))
                    } else {
                        observer(.error(FileClientError.invalidResponse(request, nil)))
                    }
                } else {
                    observer(.error(FileClientError.invalidResponse(request, nil)))
                }
            }

            task.resume()
            return Disposables.create { task.cancel() }
        }
    }
}
