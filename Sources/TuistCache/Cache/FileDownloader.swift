import Foundation
import RxSwift
import TSCBasic
import TuistSupport

enum FileDownloaderError: LocalizedError, FatalError {
    case noLocalURL(String)
    case invalidResponse(String)
    case urlSessionError(String, Error)
    case moveFileError(String, Error)

    // MARK: - FatalError

    var description: String {
        switch self {
        case let .noLocalURL(frameworkName):
            return "The download of framework \(frameworkName) from the cache succeeded, but the file doesn't exist locally."
        case let .invalidResponse(frameworkName):
            return "Invalid URL response when downloading framework \(frameworkName)"
        case let .urlSessionError(frameworkName, error):
            if let error = error as? LocalizedError {
                return error.localizedDescription
            } else {
                return "URL session error when downloading the framework \(frameworkName)"
            }
        case let .moveFileError(frameworkName, error):
            let output = "Error while moving downloaded framework \(frameworkName)."
            if let error = error as? LocalizedError {
                return "\(output). Error: \(error.localizedDescription)"
            } else {
                return output
            }
        }
    }

    var type: ErrorType {
        switch self {
        case .noLocalURL: return .abort
        case .invalidResponse: return .bug
        case .moveFileError: return .bug
        case .urlSessionError: return .bug
        }
    }

    // MARK: - LocalizedError

    public var errorDescription: String? { description }
}

class FileDownloader {
    private let urlSession: URLSession
    private let fileManager: FileManager

    init(urlSession: URLSession = URLSession.shared, fileManager: FileManager = FileManager.default) {
        self.urlSession = urlSession
        self.fileManager = fileManager
    }

    func download(frameworkName: String, url: URL, in directory: AbsolutePath) -> Single<AbsolutePath> {
        Single.create { observer -> Disposable in
            let task = self.urlSession.downloadTask(with: url) { localURL, response, networkError in
                if let networkError = networkError {
                    observer(.error(FileDownloaderError.urlSessionError(frameworkName, networkError)))
                } else if let response = response as? HTTPURLResponse {
                    // Local URL
                    guard let localURL = localURL else {
                        observer(.error(FileDownloaderError.noLocalURL(frameworkName)))
                        return
                    }

                    self.processResponse(
                        response,
                        frameworkName: frameworkName,
                        observer: observer,
                        localURL: localURL,
                        directory: directory
                    )
                } else {
                    observer(.error(FileDownloaderError.invalidResponse(frameworkName)))
                }
            }

            task.resume()
            return Disposables.create { task.cancel() }
        }
    }

    // MARK: - Fileprivate

    private func processResponse(_ response: HTTPURLResponse,
                                 frameworkName: String,
                                 observer: (SingleEvent<AbsolutePath>) -> Void,
                                 localURL: URL,
                                 directory: AbsolutePath) {
        // HTTPURLResponse
        switch response.statusCode {
        case 200 ..< 300:
            // Success
            do {
                try fileManager.moveItem(atPath: localURL.path, toPath: directory.pathString)
                observer(.success(directory))
            } catch {
                observer(.error(FileDownloaderError.moveFileError(frameworkName, error)))
            }
        default: // Error
            observer(.error(FileDownloaderError.invalidResponse(frameworkName)))
        }
    }
}
