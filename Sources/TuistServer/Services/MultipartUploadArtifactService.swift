import FileSystem
import Foundation
import Mockable
import Path
import TuistSupport

public struct MultipartUploadArtifactPart {
    public let number: Int
    public let contentLength: Int
}

enum MultipartUploadArtifactServiceError: FatalError {
    case cannotCreateInputStream(AbsolutePath)
    case noURLResponse(URL?)
    case missingEtag(URL?)
    case invalidMultipartUploadURL(String)

    var type: ErrorType {
        switch self {
        case .cannotCreateInputStream, .noURLResponse, .missingEtag, .invalidMultipartUploadURL: return .abort
        }
    }

    var description: String {
        switch self {
        case let .cannotCreateInputStream(path):
            return "Couldn't create the file stream to multi-part upload file at path \(path.pathString)"
        case let .noURLResponse(url):
            if let url {
                return "The response from request to URL \(url.absoluteString) doesnt' have the expected type HTTPURLResponse"
            } else {
                return "Received a response that doesn't have the expected type HTTPURLResponse"
            }
        case let .missingEtag(url):
            if let url {
                return "The response from request to URL \(url.absoluteString) lacks the etag HTTP header"
            } else {
                return "Received a response lacking the etag HTTP header"
            }
        case let .invalidMultipartUploadURL(url):
            return "Received an invalid URL for a multi-part upload: \(url)"
        }
    }
}

@Mockable
public protocol MultipartUploadArtifactServicing {
    func multipartUploadArtifact(
        artifactPath: AbsolutePath,
        generateUploadURL: @escaping (MultipartUploadArtifactPart) async throws -> String,
        updateProgress: @escaping (Double) -> Void
    ) async throws -> [(etag: String, partNumber: Int)]
}

public struct MultipartUploadArtifactService: MultipartUploadArtifactServicing {
    private let urlSession: URLSession
    private let fileSystem: FileSysteming

    public init(
        urlSession: URLSession = .tuistShared,
        fileSystem: FileSysteming = FileSystem()
    ) {
        self.urlSession = urlSession
        self.fileSystem = fileSystem
    }

    public func multipartUploadArtifact(
        artifactPath: AbsolutePath,
        generateUploadURL: @escaping (MultipartUploadArtifactPart) async throws -> String,
        updateProgress: @escaping (Double) -> Void
    ) async throws -> [(etag: String, partNumber: Int)] {
        let partSize = 10 * 1024 * 1024
        guard let inputStream = InputStream(url: artifactPath.url) else {
            throw MultipartUploadArtifactServiceError.cannotCreateInputStream(artifactPath)
        }

        let size = try await fileSystem.fileSizeInBytes(at: artifactPath) ?? 0
        let numberOfParts = Int(ceil(Double(Int(size)) / Double(partSize)))

        inputStream.open()

        defer { inputStream.close() }

        var buffer = [UInt8](repeating: 0, count: partSize)

        let uploadedParts: ThreadSafe<[(etag: String, partNumber: Int)]> = ThreadSafe([])
        let partNumber = ThreadSafe(1)

        try await withThrowingTaskGroup(of: Void.self) { group in
            while inputStream.hasBytesAvailable {
                let bytesRead = inputStream.read(&buffer, maxLength: partSize)

                if bytesRead > 0 {
                    let partData = Data(bytes: buffer, count: bytesRead)
                    let currentPartNumber = partNumber.value
                    partNumber.mutate { $0 += 1 }
                    group.addTask {
                        let uploadURLString = try await generateUploadURL(MultipartUploadArtifactPart(
                            number: currentPartNumber,
                            contentLength: bytesRead
                        ))
                        guard let url = URL(string: uploadURLString) else {
                            throw MultipartUploadArtifactServiceError.invalidMultipartUploadURL(uploadURLString)
                        }

                        let request = uploadRequest(url: url, fileSize: UInt64(bytesRead), data: partData)
                        let etag = try await upload(for: request)
                        uploadedParts.mutate { $0.append((etag: etag, partNumber: currentPartNumber)) }
                        updateProgress(Double(uploadedParts.value.count) / Double(numberOfParts))
                    }
                }
            }
            try await group.waitForAll()
        }

        return uploadedParts
            .value
            .sorted(by: { $0.partNumber < $1.partNumber })
    }

    private func upload(for request: URLRequest) async throws -> String {
        let (_, response) = try await urlSession.data(for: request)
        guard let urlResponse = response as? HTTPURLResponse else {
            throw MultipartUploadArtifactServiceError.noURLResponse(request.url)
        }
        guard let etag = urlResponse.value(forHTTPHeaderField: "Etag") else {
            throw MultipartUploadArtifactServiceError.missingEtag(request.url)
        }
        return etag.spm_chomp()
    }

    private func uploadRequest(url: URL, fileSize: UInt64, data: Data) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
        request.setValue(String(fileSize), forHTTPHeaderField: "Content-Length")
        request.setValue("zip", forHTTPHeaderField: "Content-Encoding")
        request.httpBody = data
        return request
    }

    private struct UploadPart {
        let url: URL
        let fileSize: UInt64
        let data: Data
        let partNumber: Int
    }
}
