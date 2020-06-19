import Foundation
import RxSwift
import TSCBasic

enum FileUploaderError: LocalizedError {
    case unreachableFileSize(String)
    case urlSessionError(Error)
    case serverSideError(HTTPURLResponse)
    case invalidResponse

    public var errorDescription: String? {
        switch self {
        case let .unreachableFileSize(path): return "Could not get the file size at path \(path)"
        case let .urlSessionError(error):
            if let error = error as? LocalizedError {
                return error.localizedDescription
            } else {
                return "Received a session error while uploading file."
            }
        case .invalidResponse: return "Received unexpected response from the network while uploading file."
        case let .serverSideError(response):
            return "Error returned by the server, code: \(response.statusCode). Reponse: \(response.description)"
        }
    }
}

public class FileUploader {
    
    // MARK: - Attributes
    
    let session: URLSession
    let fileManager: FileManager
    
    // MARK: - Init
    
    public init(session: URLSession = URLSession.shared,
                fileManager: FileManager = FileManager.default
    ) {
        self.session = session
        self.fileManager = fileManager
    }
    
    // MARK: - Public
    
    public func upload(file: AbsolutePath, hash: String, to url: URL) -> Single<Bool> {
        return Single<Bool>.create { observer -> Disposable in
            do {
                let fileSize = try self.fileSize(path: file.pathString)
                let fileData = try Data(contentsOf: file.url)
                
                let request = self.uploadRequest(url: url, fileSize: fileSize, data: fileData)
                let uploadTask = self.session.dataTask(with: request) { data, response, error in
                    if let error = error {
                        observer(.error(FileUploaderError.urlSessionError(error)))
                    } else if let data = data, let response = response as? HTTPURLResponse {
                        print(response)
                        print("data: " + (String(data: data, encoding: .utf8) ?? ""))

                        switch response.statusCode {
                        case 200 ..< 300:
                            observer(.success(true))
                        default: // Error
                            observer(.error(FileUploaderError.serverSideError(response)))
                        }
                    } else {
                        observer(.error(FileUploaderError.invalidResponse))
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
    
    private func fileSize(path: String) throws -> UInt64 {
        let attr = try self.fileManager.attributesOfItem(atPath: path)
        guard let size = attr[FileAttributeKey.size] as? UInt64 else { throw FileUploaderError.unreachableFileSize(path) }
        return size
    }
}
