import Foundation
import Path

#if os(macOS)
    import TuistSupport
#endif

#if os(macOS)
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
            self.init(session: FileClient.defaultSession())
        }

        private init(session: URLSession) {
            self.session = session
        }

        private static func defaultSession() -> URLSession {
            let configuration = URLSessionConfiguration.default
            configuration.timeoutIntervalForRequest = 30
            configuration.timeoutIntervalForResource = 180
            return URLSession(configuration: configuration)
        }

        // MARK: - Public

        public func download(url: URL) async throws -> AbsolutePath {
            let request = URLRequest(url: url)
            let startTime = Date()
            do {
                let (localUrl, response) = try await session.download(for: request)
                let endTime = Date()
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FileClientError.invalidResponse(request, nil)
                }
                await recordDownload(
                    request: request,
                    response: httpResponse,
                    startTime: startTime,
                    endTime: endTime
                )
                if successStatusCodeRange.contains(httpResponse.statusCode) {
                    return try AbsolutePath(validating: localUrl.path)
                } else {
                    throw FileClientError.invalidResponse(request, nil)
                }
            } catch {
                let endTime = Date()
                await recordDownloadError(request: request, error: error, startTime: startTime, endTime: endTime)
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
            let startTime = Date()
            do {
                let (_, response) = try await session.data(for: request)
                let endTime = Date()
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw FileClientError.invalidResponse(request, file)
                }
                await recordUpload(
                    request: request,
                    response: httpResponse,
                    requestBodySize: Int(fileSize),
                    startTime: startTime,
                    endTime: endTime
                )
                if successStatusCodeRange.contains(httpResponse.statusCode) {
                    return true
                } else {
                    throw FileClientError.serverSideError(request, httpResponse, file)
                }
            } catch {
                let endTime = Date()
                await recordUploadError(
                    request: request,
                    error: error,
                    requestBodySize: Int(fileSize),
                    startTime: startTime,
                    endTime: endTime
                )
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

        private func recordDownload(
            request: URLRequest,
            response: HTTPURLResponse,
            startTime: Date,
            endTime: Date
        ) async {
            guard let recorder = HARRecorder.current else { return }
            let entry = createHAREntry(
                request: request,
                response: response,
                requestBodySize: 0,
                responseBodySize: nil,
                startTime: startTime,
                endTime: endTime
            )
            await recorder.record(entry)
        }

        private func recordDownloadError(
            request: URLRequest,
            error: Error,
            startTime: Date,
            endTime: Date
        ) async {
            guard let recorder = HARRecorder.current else { return }
            let entry = createHARErrorEntry(
                request: request,
                error: error,
                requestBodySize: 0,
                startTime: startTime,
                endTime: endTime
            )
            await recorder.record(entry)
        }

        private func recordUpload(
            request: URLRequest,
            response: HTTPURLResponse,
            requestBodySize: Int,
            startTime: Date,
            endTime: Date
        ) async {
            guard let recorder = HARRecorder.current else { return }
            let entry = createHAREntry(
                request: request,
                response: response,
                requestBodySize: requestBodySize,
                responseBodySize: nil,
                startTime: startTime,
                endTime: endTime
            )
            await recorder.record(entry)
        }

        private func recordUploadError(
            request: URLRequest,
            error: Error,
            requestBodySize: Int,
            startTime: Date,
            endTime: Date
        ) async {
            guard let recorder = HARRecorder.current else { return }
            let entry = createHARErrorEntry(
                request: request,
                error: error,
                requestBodySize: requestBodySize,
                startTime: startTime,
                endTime: endTime
            )
            await recorder.record(entry)
        }

        private func createHAREntry(
            request: URLRequest,
            response: HTTPURLResponse,
            requestBodySize: Int,
            responseBodySize: Int?,
            startTime: Date,
            endTime: Date
        ) -> HAR.Entry {
            let durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)
            let url = request.url?.absoluteString ?? ""

            let requestHeaders = HARRecorder.filterSensitiveHeaders(
                (request.allHTTPHeaderFields ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) }
            )

            let responseHeaders = HARRecorder.filterSensitiveHeaders(
                (response.allHeaderFields as? [String: String] ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) }
            )

            let queryParameters = extractQueryParameters(from: url)
            let mimeType = response.mimeType ?? "application/octet-stream"

            return HAR.Entry(
                startedDateTime: startTime,
                time: durationMs,
                request: HAR.Request(
                    method: request.httpMethod ?? "GET",
                    url: url,
                    httpVersion: "HTTP/1.1",
                    cookies: [],
                    headers: requestHeaders,
                    queryString: queryParameters,
                    postData: nil,
                    headersSize: -1,
                    bodySize: requestBodySize
                ),
                response: HAR.Response(
                    status: response.statusCode,
                    statusText: HTTPURLResponse.localizedString(forStatusCode: response.statusCode),
                    httpVersion: "HTTP/1.1",
                    cookies: [],
                    headers: responseHeaders,
                    content: HAR.Content(
                        size: responseBodySize ?? Int(response.expectedContentLength),
                        mimeType: mimeType
                    ),
                    redirectURL: "",
                    headersSize: -1,
                    bodySize: responseBodySize ?? Int(response.expectedContentLength)
                ),
                timings: HAR.Timings(
                    send: 0,
                    wait: durationMs,
                    receive: 0
                )
            )
        }

        private func createHARErrorEntry(
            request: URLRequest,
            error: Error,
            requestBodySize: Int,
            startTime: Date,
            endTime: Date
        ) -> HAR.Entry {
            let durationMs = Int((endTime.timeIntervalSince(startTime)) * 1000)
            let url = request.url?.absoluteString ?? ""

            let requestHeaders = HARRecorder.filterSensitiveHeaders(
                (request.allHTTPHeaderFields ?? [:]).map { HAR.Header(name: $0.key, value: $0.value) }
            )

            let queryParameters = extractQueryParameters(from: url)
            let errorMessage = String(describing: error)

            return HAR.Entry(
                startedDateTime: startTime,
                time: durationMs,
                request: HAR.Request(
                    method: request.httpMethod ?? "GET",
                    url: url,
                    httpVersion: "HTTP/1.1",
                    cookies: [],
                    headers: requestHeaders,
                    queryString: queryParameters,
                    postData: nil,
                    headersSize: -1,
                    bodySize: requestBodySize
                ),
                response: HAR.Response(
                    status: 0,
                    statusText: "Error",
                    httpVersion: "HTTP/1.1",
                    cookies: [],
                    headers: [],
                    content: HAR.Content(
                        size: errorMessage.utf8.count,
                        mimeType: "text/plain",
                        text: errorMessage
                    ),
                    redirectURL: "",
                    headersSize: -1,
                    bodySize: errorMessage.utf8.count
                ),
                timings: HAR.Timings(
                    send: 0,
                    wait: durationMs,
                    receive: 0
                )
            )
        }

        private func extractQueryParameters(from urlString: String) -> [HAR.QueryParameter] {
            guard let url = URL(string: urlString),
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
                  let queryItems = components.queryItems
            else {
                return []
            }
            return queryItems.map { HAR.QueryParameter(name: $0.name, value: $0.value ?? "") }
        }
    }
#endif
