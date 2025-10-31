#if canImport(Command)
    import Command
    import FileSystem
    import Foundation
    import Mockable
    import Path

    public struct MultipartUploadArtifactPart {
        public let number: Int
        public let contentLength: Int
    }

    enum MultipartUploadArtifactServiceError: LocalizedError {
        case cannotCreateInputStream(AbsolutePath)
        case noURLResponse(URL?)
        case missingEtag(URL?, statusCode: Int, body: String)
        case invalidMultipartUploadURL(String)

        var errorDescription: String? {
            switch self {
            case let .cannotCreateInputStream(path):
                return "Couldn't create the file stream to multi-part upload file at path \(path.pathString)"
            case let .noURLResponse(url):
                if let url {
                    return "The response from request to URL \(url.absoluteString) doesnt' have the expected type HTTPURLResponse"
                } else {
                    return "Received a response that doesn't have the expected type HTTPURLResponse"
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
        private let urlSession: URLSession
        private let fileSystem: FileSysteming
        private let retryProvider: RetryProviding

        public init(
            urlSession: URLSession = .tuistShared,
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
                }
                try await group.waitForAll()
            }

            return uploadedParts
                .value
                .sorted(by: { $0.partNumber < $1.partNumber })
        }

        private func upload(for request: URLRequest) async throws -> String {
            let (data, response) = try await urlSession.data(for: request)
            guard let urlResponse = response as? HTTPURLResponse else {
                throw MultipartUploadArtifactServiceError.noURLResponse(request.url)
            }
            guard let etag = urlResponse.value(forHTTPHeaderField: "Etag") else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw MultipartUploadArtifactServiceError.missingEtag(request.url, statusCode: urlResponse.statusCode, body: body)
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
#endif
