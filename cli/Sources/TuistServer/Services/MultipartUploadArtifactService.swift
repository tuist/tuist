#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import FileSystem
import Foundation
import Mockable
import Path
import TuistHTTP
import TuistThreadSafe

public struct MultipartUploadArtifactPart {
    public let number: Int
    public let contentLength: Int

    public init(number: Int, contentLength: Int) {
        self.number = number
        self.contentLength = contentLength
    }
}

enum MultipartUploadArtifactServiceError: LocalizedError {
    case cannotCreateInputStream(AbsolutePath)
    case failedToReadArtifact(AbsolutePath, String)
    case incompleteArtifactRead(AbsolutePath, expectedBytes: UInt64, readBytes: UInt64)
    case noURLResponse(URL?)
    case uploadFailed(URL?, statusCode: Int, body: String)
    case missingEtag(URL?, statusCode: Int, body: String)
    case invalidMultipartUploadURL(String)

    var errorDescription: String? {
        switch self {
        case let .cannotCreateInputStream(path):
            return "Couldn't create the file stream to multi-part upload file at path \(path.pathString)"
        case let .failedToReadArtifact(path, reason):
            return "Failed to read artifact at path \(path.pathString) for multipart upload: \(reason)"
        case let .incompleteArtifactRead(path, expectedBytes, readBytes):
            return """
            Failed to read the complete artifact at path \(path.pathString) for multipart upload:
            - Expected bytes: \(expectedBytes)
            - Read bytes: \(readBytes)
            """
        case let .noURLResponse(url):
            if let url {
                return "The response from request to URL \(url.absoluteString) doesnt' have the expected type HTTPURLResponse"
            } else {
                return "Received a response that doesn't have the expected type HTTPURLResponse"
            }
        case let .uploadFailed(url, statusCode, body):
            if let url {
                return """
                The multipart upload request to URL \(url.absoluteString) failed with status code \(statusCode):
                - Body: \(body)
                """
            } else {
                return """
                The multipart upload request failed with status code \(statusCode):
                - Body: \(body)
                """
            }
        case let .missingEtag(url, statusCode, body):
            if let url {
                return """
                The response from request to URL \(
                    url
                        .absoluteString
                ) failed with status code \(statusCode) and lacks the etag HTTP header:
                - Body: \(body)
                """
            } else {
                return """
                Received a response with status code \(statusCode) lacking the etag HTTP header:
                - Body: \(body)

                """
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
    /// Maximum number of parts uploaded concurrently — and therefore buffered in memory — during a
    /// single artifact upload. Peak memory is bounded by `maxConcurrentParts * partSize` regardless
    /// of the artifact's total size. Without this cap the read loop races ahead of the uploads and
    /// holds every part in memory at once, so memory grows with the artifact and OOMs on multi-GB
    /// uploads (e.g. a large shard test-products bundle).
    private static let maxConcurrentParts = 10

    private let urlSession: URLSession?
    private let fileSystem: FileSysteming
    private let retryProvider: RetryProviding

    public init(
        urlSession: URLSession? = nil,
        fileSystem: FileSysteming = FileSystem(),
        retryProvider: RetryProviding = RetryProvider()
    ) {
        self.urlSession = urlSession
        self.fileSystem = fileSystem
        self.retryProvider = retryProvider
    }

    public func multipartUploadArtifact(
        artifactPath: AbsolutePath,
        generateUploadURL: @escaping (MultipartUploadArtifactPart) async throws -> String,
        updateProgress: @escaping (Double) -> Void
    ) async throws -> [(etag: String, partNumber: Int)] {
        let size = try await fileSizeInBytes(at: artifactPath)
        let uploadResult = try await uploadParts(
            artifactPath: artifactPath,
            fileSize: size,
            generateUploadURL: generateUploadURL,
            updateProgress: updateProgress
        )
        let currentSize = try await fileSizeInBytes(at: artifactPath)

        guard uploadResult.readBytes == size, currentSize == size else {
            throw MultipartUploadArtifactServiceError.incompleteArtifactRead(
                artifactPath,
                expectedBytes: currentSize,
                readBytes: uploadResult.readBytes
            )
        }

        return uploadResult.uploadedParts
            .sorted(by: { $0.partNumber < $1.partNumber })
    }

    private func fileSizeInBytes(at path: AbsolutePath) async throws -> UInt64 {
        guard let metadata = try await fileSystem.fileMetadata(at: path) else { return 0 }
        return UInt64(metadata.size)
    }

    private func uploadParts(
        artifactPath: AbsolutePath,
        fileSize: UInt64,
        generateUploadURL: @escaping (MultipartUploadArtifactPart) async throws -> String,
        updateProgress: @escaping (Double) -> Void
    ) async throws -> (readBytes: UInt64, uploadedParts: [(etag: String, partNumber: Int)]) {
        let partSize = 10 * 1024 * 1024
        guard let inputStream = InputStream(url: URL(fileURLWithPath: artifactPath.pathString)) else {
            throw MultipartUploadArtifactServiceError.cannotCreateInputStream(artifactPath)
        }

        let numberOfParts = Int(ceil(Double(Int(fileSize)) / Double(partSize)))

        inputStream.open()
        defer { inputStream.close() }

        var buffer = [UInt8](repeating: 0, count: partSize)
        var readBytes: UInt64 = 0
        let uploadedParts: ThreadSafe<[(etag: String, partNumber: Int)]> = ThreadSafe([])
        let partNumber = ThreadSafe(1)

        try await withThrowingTaskGroup(of: Void.self) { group in
            var partsInFlight = 0
            while let partData = try readPart(
                from: inputStream,
                buffer: &buffer,
                maxLength: partSize,
                artifactPath: artifactPath
            ) {
                readBytes += UInt64(partData.count)
                if partsInFlight >= Self.maxConcurrentParts {
                    try await group.next()
                    partsInFlight -= 1
                }
                addUploadTask(
                    to: &group,
                    partData: partData,
                    partNumber: partNumber,
                    numberOfParts: numberOfParts,
                    uploadedParts: uploadedParts,
                    generateUploadURL: generateUploadURL,
                    updateProgress: updateProgress
                )
                partsInFlight += 1
            }
            try await group.waitForAll()
        }

        return (readBytes: readBytes, uploadedParts: uploadedParts.value)
    }

    private func addUploadTask(
        to group: inout ThrowingTaskGroup<Void, any Error>,
        partData: Data,
        partNumber: ThreadSafe<Int>,
        numberOfParts: Int,
        uploadedParts: ThreadSafe<[(etag: String, partNumber: Int)]>,
        generateUploadURL: @escaping (MultipartUploadArtifactPart) async throws -> String,
        updateProgress: @escaping (Double) -> Void
    ) {
        let bytesRead = partData.count
        let currentPartNumber = partNumber.value
        partNumber.mutate { $0 += 1 }
        group.addTask {
            try await retryProvider.runWithRetries {
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

    private func readPart(
        from inputStream: InputStream,
        buffer: inout [UInt8],
        maxLength: Int,
        artifactPath: AbsolutePath
    ) throws -> Data? {
        var partData = Data()
        partData.reserveCapacity(maxLength)

        while partData.count < maxLength {
            let remainingBytes = maxLength - partData.count
            let bytesRead = inputStream.read(&buffer, maxLength: min(buffer.count, remainingBytes))

            if bytesRead < 0 {
                let reason = inputStream.streamError?.localizedDescription ?? "unknown stream error"
                throw MultipartUploadArtifactServiceError.failedToReadArtifact(artifactPath, reason)
            }

            guard bytesRead > 0 else { break }
            partData.append(buffer, count: bytesRead)
        }

        return partData.isEmpty ? nil : partData
    }

    private func upload(for request: URLRequest) async throws -> String {
        let urlSession = urlSession ?? .tuistShared
        let (data, response) = try await urlSession.data(for: request)
        guard let urlResponse = response as? HTTPURLResponse else {
            throw MultipartUploadArtifactServiceError.noURLResponse(request.url)
        }
        guard (200 ..< 300).contains(urlResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MultipartUploadArtifactServiceError.uploadFailed(
                request.url,
                statusCode: urlResponse.statusCode,
                body: body
            )
        }
        guard let etag = urlResponse.value(forHTTPHeaderField: "Etag") else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw MultipartUploadArtifactServiceError.missingEtag(request.url, statusCode: urlResponse.statusCode, body: body)
        }
        return etag.trimmingCharacters(in: .whitespacesAndNewlines)
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
