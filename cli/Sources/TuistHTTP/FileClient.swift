import FileSystem
import Foundation
import Path

#if canImport(TuistHAR)
    import Synchronization
    import TuistHAR
    import TuistLogging
    import TuistSupport
#endif

#if canImport(TuistHAR)
    enum FileClientError: LocalizedError, FatalError, HTTPStatusCodeError {
        case urlSessionError(URLRequest, Error, AbsolutePath?)
        case serverSideError(URLRequest, HTTPURLResponse, AbsolutePath?)
        case invalidResponse(URLRequest, AbsolutePath?)
        case noLocalURL(URLRequest)

        // MARK: - HTTPStatusCodeError

        var httpStatusCode: Int {
            guard case let .serverSideError(_, response, _) = self else { return 0 }
            return response.statusCode
        }

        /// Only a status the server answered with can make a repeated transfer pointless.
        var isRetryable: Bool {
            guard case .serverSideError = self else { return true }
            return !HTTPRetryPolicy.isPermanentClientError(statusCode: httpStatusCode)
        }

        // MARK: - FatalError

        var description: String {
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
            guard let path else { return "" }
            return " for file at path \(path.pathString)"
        }

        // MARK: - LocalizedError

        var errorDescription: String? { description }
    }

    public protocol FileClienting {
        func upload(file: AbsolutePath, hash: String, to url: URL) async throws -> Bool
        func download(url: URL, to destination: AbsolutePath) async throws
    }

    public struct FileClient: FileClienting {
        // MARK: - Attributes

        private let session: URLSession?
        private let fileSystem: FileSysteming
        private let partialDownloads = PartialDownloads()
        private let successStatusCodeRange = 200 ..< 300

        // MARK: - Init

        public init(
            session: URLSession? = nil,
            fileSystem: FileSysteming = FileSystem()
        ) {
            self.session = session
            self.fileSystem = fileSystem
        }

        // MARK: - Public

        /// The body is written to `<destination>.partial` as it arrives. When an attempt fails, the bytes it
        /// received stay there, and the next call for the same URL and destination on this client asks only for
        /// the rest (`Range`, guarded by `If-Range` with the first response's validator). A server that answers
        /// with the whole object, or with a range that does not continue the file, restarts it from zero.
        public func download(url: URL, to destination: AbsolutePath) async throws {
            let partialPath = destination.parentDirectory.appending(component: "\(destination.basename).partial")
            let session = resolvedSession()
            if let validator = partialDownloads.validator(url: url, destination: destination),
               let size = try? await fileSystem.fileMetadata(at: partialPath)?.size, size > 0,
               try await attemptDownload(
                   url: url, to: destination, partialPath: partialPath,
                   resumingFrom: Int64(size), validator: validator, session: session
               )
            {
                return
            }
            try await attemptDownload(
                url: url, to: destination, partialPath: partialPath, resumingFrom: 0, validator: nil, session: session
            )
        }

        public func upload(file: AbsolutePath, hash _: String, to url: URL) async throws -> Bool {
            guard let metadata = try await fileSystem.fileMetadata(at: file) else {
                throw FileClientError.noLocalURL(URLRequest(url: url))
            }
            let fileSize = UInt64(metadata.size)
            let fileData = try Data(contentsOf: file.url)
            let request = uploadRequest(url: url, fileSize: fileSize, data: fileData)
            let session = resolvedSession()
            do {
                let (_, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    let error = FileClientError.invalidResponse(request, file)
                    HARRecorder.recordDetached { recorder in
                        await Self.recordUploadError(
                            request: request,
                            error: error,
                            requestBodySize: Int(fileSize),
                            recorder: recorder
                        )
                    }
                    throw error
                }
                HARRecorder.recordDetached { recorder in
                    await Self.recordUpload(
                        request: request,
                        response: httpResponse,
                        requestBodySize: Int(fileSize),
                        recorder: recorder
                    )
                }
                if successStatusCodeRange.contains(httpResponse.statusCode) {
                    return true
                } else {
                    throw FileClientError.serverSideError(request, httpResponse, file)
                }
            } catch let error as FileClientError {
                throw error
            } catch {
                HARRecorder.recordDetached { recorder in
                    await Self.recordUploadError(
                        request: request,
                        error: error,
                        requestBodySize: Int(fileSize),
                        recorder: recorder
                    )
                }
                throw FileClientError.urlSessionError(request, error, file)
            }
        }

        // MARK: - Private

        /// Returns false when the server did not continue the partial file, which is then discarded.
        @discardableResult
        private func attemptDownload(
            url: URL,
            to destination: AbsolutePath,
            partialPath: AbsolutePath,
            resumingFrom offset: Int64,
            validator: String?,
            session: URLSession
        ) async throws -> Bool {
            var rangeRequest = URLRequest(url: url)
            if let validator {
                rangeRequest.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
                rangeRequest.setValue(validator, forHTTPHeaderField: "If-Range")
            }
            let request = rangeRequest
            let writer = PartialFileWriter(path: partialPath, resumeOffset: offset, validator: validator)
            let result: PartialFileWriter.Result
            do {
                result = try await writer.run(request, session: session)
            } catch {
                if let fileValidator = writer.fileValidator, (try? await fileSystem.exists(partialPath)) == true {
                    partialDownloads.remember(url: url, destination: destination, validator: fileValidator)
                } else {
                    partialDownloads.forget(destination: destination)
                    try? await fileSystem.remove(partialPath)
                }
                HARRecorder.recordDetached { recorder in
                    await Self.recordDownloadError(request: request, error: error, recorder: recorder)
                }
                throw FileClientError.urlSessionError(request, error, destination)
            }

            if let response = result.response {
                HARRecorder.recordDetached { recorder in
                    await Self.recordDownload(request: request, response: response, recorder: recorder)
                }
            }
            switch result {
            case .completed:
                partialDownloads.forget(destination: destination)
                try await fileSystem.move(from: partialPath, to: destination)
                return true
            case .rangeNotContinued:
                partialDownloads.forget(destination: destination)
                try? await fileSystem.remove(partialPath)
                return false
            case let .serverSideError(response):
                throw FileClientError.serverSideError(request, response, nil)
            case .invalidResponse:
                let error = FileClientError.invalidResponse(request, nil)
                HARRecorder.recordDetached { recorder in
                    await Self.recordDownloadError(request: request, error: error, recorder: recorder)
                }
                throw error
            }
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

        private func resolvedSession() -> URLSession {
            session ?? .tuistLargeTransfer
        }

        // MARK: - HAR Recording

        private static func recordDownload(request: URLRequest, response: HTTPURLResponse, recorder: HARRecorder) async {
            guard let url = request.url else { return }
            let metadata = await retrieveHARMetadata(for: url)
            await recorder.recordRequest(
                request: request,
                response: response,
                requestBody: nil,
                responseBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize,
                responseHeadersSize: metadata.responseHeadersSize
            )
        }

        private static func recordDownloadError(request: URLRequest, error: Error, recorder: HARRecorder) async {
            guard let url = request.url else { return }
            let metadata = await retrieveHARMetadata(for: url)
            await recorder.recordError(
                request: request,
                error: error,
                requestBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize
            )
        }

        private static func recordUpload(
            request: URLRequest,
            response: HTTPURLResponse,
            requestBodySize: Int,
            recorder: HARRecorder
        ) async {
            guard let url = request.url else { return }
            let metadata = await retrieveHARMetadata(for: url)
            await recorder.recordRequest(
                request: request,
                response: response,
                requestBody: nil,
                responseBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize,
                responseHeadersSize: metadata.responseHeadersSize,
                requestBodySize: requestBodySize
            )
        }

        private static func recordUploadError(
            request: URLRequest,
            error: Error,
            requestBodySize: Int,
            recorder: HARRecorder
        ) async {
            guard let url = request.url else { return }
            let metadata = await retrieveHARMetadata(for: url)
            await recorder.recordError(
                request: request,
                error: error,
                requestBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize,
                requestBodySize: requestBodySize
            )
        }

        private struct HARMetadataResult {
            let timings: HAR.Timings?
            let startTime: Date
            let endTime: Date
            let httpVersion: String?
            let requestHeadersSize: Int?
            let responseHeadersSize: Int?
        }

        private static func retrieveHARMetadata(for url: URL) async -> HARMetadataResult {
            guard let metrics = await URLSessionMetricsDelegate.shared.retrieveMetrics(for: url),
                  let harMetadata = URLSessionMetricsDelegate.extractHARMetadata(from: metrics)
            else {
                let now = Date()
                return HARMetadataResult(
                    timings: nil,
                    startTime: now,
                    endTime: now,
                    httpVersion: nil,
                    requestHeadersSize: nil,
                    responseHeadersSize: nil
                )
            }
            return HARMetadataResult(
                timings: harMetadata.timings,
                startTime: harMetadata.startTime,
                endTime: harMetadata.endTime,
                httpVersion: harMetadata.httpVersion,
                requestHeadersSize: harMetadata.requestHeadersSize,
                responseHeadersSize: harMetadata.responseHeadersSize
            )
        }
    }

    /// The validators of downloads that failed with bytes left in their partial file, by destination.
    private final class PartialDownloads: Sendable {
        private struct Entry {
            let url: URL
            let validator: String
        }

        private let entries = Mutex<[AbsolutePath: Entry]>([:])

        func validator(url: URL, destination: AbsolutePath) -> String? {
            entries.withLock { entries in
                entries[destination].flatMap { $0.url == url ? $0.validator : nil }
            }
        }

        func remember(url: URL, destination: AbsolutePath, validator: String) {
            entries.withLock { $0[destination] = Entry(url: url, validator: validator) }
        }

        func forget(destination: AbsolutePath) {
            _ = entries.withLock { $0.removeValue(forKey: destination) }
        }
    }

    /// Writes one response body to a file as it arrives, so the bytes of a failed transfer stay on disk. Its
    /// delegate methods run on the session's serial delegate queue.
    private final class PartialFileWriter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
        enum Result {
            case completed(HTTPURLResponse)
            /// A 416, or a 206 that does not continue the file from `resumeOffset` with the same validator.
            case rangeNotContinued(HTTPURLResponse)
            case serverSideError(HTTPURLResponse)
            case invalidResponse

            var response: HTTPURLResponse? {
                switch self {
                case let .completed(response), let .rangeNotContinued(response), let .serverSideError(response):
                    return response
                case .invalidResponse:
                    return nil
                }
            }
        }

        private let path: AbsolutePath
        private let resumeOffset: Int64
        private let validator: String?
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Result, Error>?
        private var handle: FileHandle?
        private var earlyResult: Result?
        private var writeError: Error?
        private var _fileValidator: String?

        /// The validator of the object whose bytes are in the file, or nil when they cannot be resumed.
        var fileValidator: String? {
            lock.withLock { _fileValidator }
        }

        init(path: AbsolutePath, resumeOffset: Int64, validator: String?) {
            self.path = path
            self.resumeOffset = resumeOffset
            self.validator = validator
            _fileValidator = validator
        }

        func run(_ request: URLRequest, session: URLSession) async throws -> Result {
            let task = session.dataTask(with: request)
            task.delegate = self
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    lock.withLock { self.continuation = continuation }
                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        }

        func urlSession(
            _: URLSession,
            dataTask _: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            guard let response = response as? HTTPURLResponse else {
                earlyResult = .invalidResponse
                return completionHandler(.cancel)
            }
            let statusCode = response.statusCode
            guard (200 ..< 300).contains(statusCode) || (statusCode == 416 && resumeOffset > 0) else {
                earlyResult = .serverSideError(response)
                return completionHandler(.cancel)
            }
            let appends = resumeOffset > 0 && statusCode == 206
            if resumeOffset > 0, statusCode == 416 || appends && !continues(response) {
                earlyResult = .rangeNotContinued(response)
                return completionHandler(.cancel)
            }
            do {
                if appends {
                    let handle = try FileHandle(forWritingTo: path.url)
                    try handle.truncate(atOffset: UInt64(resumeOffset))
                    try handle.seek(toOffset: UInt64(resumeOffset))
                    self.handle = handle
                } else {
                    FileManager.default.createFile(atPath: path.pathString, contents: nil)
                    handle = try FileHandle(forWritingTo: path.url)
                    lock.withLock { _fileValidator = Self.validator(of: response) }
                }
                completionHandler(.allow)
            } catch {
                writeError = error
                completionHandler(.cancel)
            }
        }

        func urlSession(_: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            do {
                try handle?.write(contentsOf: data)
            } catch {
                writeError = error
                dataTask.cancel()
            }
        }

        func urlSession(_: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            try? handle?.close()
            let continuation = lock.withLock {
                defer { self.continuation = nil }
                return self.continuation
            }
            if let earlyResult {
                continuation?.resume(returning: earlyResult)
            } else if let error = writeError ?? error {
                continuation?.resume(throwing: error)
            } else if let response = task.response as? HTTPURLResponse {
                continuation?.resume(returning: .completed(response))
            } else {
                continuation?.resume(returning: .invalidResponse)
            }
        }

        /// Compares the 206's own validator, not only its start: Tigris, which stores shard artifacts, ignores `If-Range`
        /// and answers a range with 206 even after the object changed.
        private func continues(_ response: HTTPURLResponse) -> Bool {
            guard let contentRange = response.value(forHTTPHeaderField: "Content-Range"),
                  contentRange.hasPrefix("bytes "),
                  let start = contentRange.dropFirst("bytes ".count).split(separator: "-").first.flatMap({ Int64($0) })
            else { return false }
            return start == resumeOffset && Self.validator(of: response) == validator
        }

        /// A strong `ETag`, else `Last-Modified`, the forms `If-Range` accepts. A body URLSession decompressed has
        /// no validator: its byte offsets are not the ones the server's ranges count.
        private static func validator(of response: HTTPURLResponse) -> String? {
            let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
            if let encoding, ["gzip", "x-gzip", "deflate", "br"].contains(encoding) { return nil }
            if let etag = response.value(forHTTPHeaderField: "ETag"), !etag.hasPrefix("W/") { return etag }
            return response.value(forHTTPHeaderField: "Last-Modified")
        }
    }
#endif // canImport(TuistHAR)
