import Foundation
import Path

#if canImport(TuistHAR)
    import TuistHAR
    import TuistSupport
#endif

#if canImport(TuistHAR)
    enum FileClientError: LocalizedError, FatalError {
        case urlSessionError(URLRequest, Error, AbsolutePath?)
        case serverSideError(URLRequest, HTTPURLResponse, AbsolutePath?)
        case invalidResponse(URLRequest, AbsolutePath?)
        case noLocalURL(URLRequest)

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
        func download(url: URL) async throws -> AbsolutePath
    }

    public class FileClient: FileClienting {
        // MARK: - Attributes

        let session: URLSession
        private let successStatusCodeRange = 200 ..< 300

        // MARK: - Init

        public convenience init() {
            self.init(session: .tuistShared)
        }

        private init(session: URLSession) {
            self.session = session
        }

        // MARK: - Public

        public func download(url: URL) async throws -> AbsolutePath {
            let request = URLRequest(url: url)
            do {
                let (localUrl, response) = try await session.download(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FileClientError.invalidResponse(request, nil)
                }
                Task.detached { [self] in
                    await recordDownload(request: request, response: httpResponse)
                }
                if successStatusCodeRange.contains(httpResponse.statusCode) {
                    return try AbsolutePath(validating: localUrl.path)
                } else {
                    throw FileClientError.invalidResponse(request, nil)
                }
            } catch {
                Task.detached { [self] in
                    await recordDownloadError(request: request, error: error)
                }
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
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FileClientError.invalidResponse(request, file)
                }
                Task.detached { [self] in
                    await recordUpload(request: request, response: httpResponse, requestBodySize: Int(fileSize))
                }
                if successStatusCodeRange.contains(httpResponse.statusCode) {
                    return true
                } else {
                    throw FileClientError.serverSideError(request, httpResponse, file)
                }
            } catch {
                Task.detached { [self] in
                    await recordUploadError(request: request, error: error, requestBodySize: Int(fileSize))
                }
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

        // MARK: - HAR Recording

        private func recordDownload(request: URLRequest, response: HTTPURLResponse) async {
            guard let recorder = HARRecorder.current, let url = request.url else { return }
            let metadata = retrieveHARMetadata(for: url)
            await recorder.recordRequest(
                url: url,
                method: request.httpMethod ?? "GET",
                requestHeaders: (request.allHTTPHeaderFields ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) },
                requestBody: nil,
                responseStatusCode: response.statusCode,
                responseStatusText: HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
                responseHeaders: (response.allHeaderFields as? [String: String] ?? [:])
                    .map { HAR.Header(name: $0.key, value: $0.value) },
                responseBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize,
                responseHeadersSize: metadata.responseHeadersSize
            )
        }

        private func recordDownloadError(request: URLRequest, error: Error) async {
            guard let recorder = HARRecorder.current, let url = request.url else { return }
            let metadata = retrieveHARMetadata(for: url)
            await recorder.recordError(
                url: url,
                method: request.httpMethod ?? "GET",
                requestHeaders: (request.allHTTPHeaderFields ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) },
                requestBody: nil,
                error: error,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize
            )
        }

        private func recordUpload(request: URLRequest, response: HTTPURLResponse, requestBodySize: Int) async {
            guard let recorder = HARRecorder.current, let url = request.url else { return }
            let metadata = retrieveHARMetadata(for: url)
            await recorder.recordRequest(
                url: url,
                method: request.httpMethod ?? "PUT",
                requestHeaders: (request.allHTTPHeaderFields ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) },
                requestBody: Data(count: requestBodySize),
                responseStatusCode: response.statusCode,
                responseStatusText: HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
                responseHeaders: (response.allHeaderFields as? [String: String] ?? [:])
                    .map { HAR.Header(name: $0.key, value: $0.value) },
                responseBody: nil,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize,
                responseHeadersSize: metadata.responseHeadersSize
            )
        }

        private func recordUploadError(request: URLRequest, error: Error, requestBodySize: Int) async {
            guard let recorder = HARRecorder.current, let url = request.url else { return }
            let metadata = retrieveHARMetadata(for: url)
            await recorder.recordError(
                url: url,
                method: request.httpMethod ?? "PUT",
                requestHeaders: (request.allHTTPHeaderFields ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) },
                requestBody: Data(count: requestBodySize),
                error: error,
                startTime: metadata.startTime,
                endTime: metadata.endTime,
                timings: metadata.timings,
                httpVersion: metadata.httpVersion,
                requestHeadersSize: metadata.requestHeadersSize
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

        private func retrieveHARMetadata(for url: URL) -> HARMetadataResult {
            guard let metrics = URLSessionMetricsDelegate.shared.retrieveMetrics(for: url),
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
#endif // canImport(TuistHAR)
