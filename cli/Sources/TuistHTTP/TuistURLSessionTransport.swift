import Foundation
import HTTPTypes
import OpenAPIRuntime
import Synchronization

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

#if canImport(TuistHAR)
    import TuistHAR
#endif

/// A custom URLSession transport that uses async/await APIs to enable metrics collection.
/// Unlike the default URLSessionTransport which uses completion handlers, this transport
/// uses `data(for:delegate:)` which triggers the URLSessionTaskDelegate methods including
/// `didFinishCollecting` for capturing detailed timing metrics.
///
/// Operations in `streamingOperationIDs` return once headers arrive, with a body that yields bytes as
/// they are received, so a body that fails partway keeps what arrived for `ArtifactResumeMiddleware`.
public struct TuistURLSessionTransport: ClientTransport {
    private let session: URLSession?
    private let streamingOperationIDs: Set<String>

    public init(session: URLSession? = nil, streamingOperationIDs: Set<String> = []) {
        self.session = session
        self.streamingOperationIDs = streamingOperationIDs
    }

    public func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let urlRequest = try await buildURLRequest(from: request, body: body, baseURL: baseURL)
        let session = resolvedSession()

        #if !canImport(FoundationNetworking)
            if streamingOperationIDs.contains(operationID) {
                return try await streamingResponse(for: urlRequest, session: session)
            }
        #endif

        #if canImport(TuistHAR)
            let metricsDelegate = TaskMetricsDelegate()
            let (data, response) = try await session.data(for: urlRequest, delegate: metricsDelegate)

            // The delegate callback is guaranteed to complete before session.data() returns,
            // so transactionMetrics is safely accessible here without race conditions.
            if let metrics = metricsDelegate.transactionMetrics,
               let url = urlRequest.url
            {
                await URLSessionMetricsDelegate.shared.storeMetrics(metrics, for: url)
            }
        #else
            let (data, response) = try await session.data(for: urlRequest, delegate: nil)
        #endif

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TuistURLSessionTransportError.invalidResponse(response)
        }

        let responseHeaders = buildHTTPFields(from: httpResponse)
        let httpResponseObj = HTTPResponse(status: .init(code: httpResponse.statusCode), headerFields: responseHeaders)

        let responseBody: HTTPBody? = data.isEmpty ? nil : HTTPBody(data)

        return (httpResponseObj, responseBody)
    }

    private func resolvedSession() -> URLSession {
        session ?? .tuistShared
    }

    #if !canImport(FoundationNetworking)
        private func streamingResponse(
            for urlRequest: URLRequest,
            session: URLSession
        ) async throws -> (HTTPResponse, HTTPBody?) {
            let task = session.dataTask(with: urlRequest)
            // The returned body owns the stream, so discarding the body cancels the task.
            let (body, bodyContinuation) = AsyncThrowingStream<ArraySlice<UInt8>, any Error>.makeStream()
            bodyContinuation.onTermination = { [weak task] termination in
                if case .cancelled = termination { task?.cancel() }
            }
            let delegate = StreamingResponseDelegate(bodyContinuation: bodyContinuation)
            return try await withTaskCancellationHandler {
                let response = try await withCheckedThrowingContinuation { continuation in
                    delegate.start(task, responseContinuation: continuation)
                }
                guard let httpResponse = response as? HTTPURLResponse else {
                    task.cancel()
                    throw TuistURLSessionTransportError.invalidResponse(response)
                }
                let httpResponseObj = HTTPResponse(
                    status: .init(code: httpResponse.statusCode),
                    headerFields: buildHTTPFields(from: httpResponse)
                )
                guard httpResponse.expectedContentLength != 0 else { return (httpResponseObj, nil) }
                let length: HTTPBody.Length = httpResponse.expectedContentLength > 0
                    ? .known(httpResponse.expectedContentLength)
                    : .unknown
                return (httpResponseObj, HTTPBody(body, length: length))
            } onCancel: {
                task.cancel()
            }
        }
    #endif

    private func buildURLRequest(from request: HTTPRequest, body: HTTPBody?, baseURL: URL) async throws -> URLRequest {
        let url = try buildURL(baseURL: baseURL, path: request.path)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        for field in request.headerFields {
            urlRequest.setValue(field.value, forHTTPHeaderField: field.name.rawName)
        }

        if let body {
            urlRequest.httpBody = try await collectBody(body)
        }

        return urlRequest
    }

    private func buildURL(baseURL: URL, path: String?) throws -> URL {
        guard let path, !path.isEmpty else {
            return baseURL
        }

        guard var baseComponents = URLComponents(url: baseURL, resolvingAgainstBaseURL: true) else {
            throw TuistURLSessionTransportError.invalidURL(baseURL)
        }

        guard let pathURL = URL(string: path, relativeTo: nil),
              let pathComponents = URLComponents(string: pathURL.absoluteString) ?? URLComponents(string: path)
        else {
            let combinedPath = baseComponents.path.isEmpty ? path : baseComponents.path + path
            baseComponents.path = combinedPath
            guard let url = baseComponents.url else {
                throw TuistURLSessionTransportError.invalidURL(baseURL)
            }
            return url
        }

        if !pathComponents.path.isEmpty {
            let basePath = baseComponents.path
            let newPath = pathComponents.path
            baseComponents.path = basePath.isEmpty ? newPath : basePath + newPath
        }

        if let newQueryItems = pathComponents.queryItems, !newQueryItems.isEmpty {
            var existingItems = baseComponents.queryItems ?? []
            existingItems.append(contentsOf: newQueryItems)
            baseComponents.queryItems = existingItems
        }

        guard let url = baseComponents.url else {
            throw TuistURLSessionTransportError.invalidURL(baseURL)
        }

        return url
    }

    private func collectBody(_ body: HTTPBody) async throws -> Data? {
        switch body.length {
        case .unknown:
            return nil
        case let .known(length):
            return try await Data(collecting: body, upTo: Int(length))
        }
    }

    private func buildHTTPFields(from response: HTTPURLResponse) -> HTTPFields {
        var fields = HTTPFields()
        if let allHeaders = response.allHeaderFields as? [String: String] {
            for (name, value) in allHeaders {
                if let fieldName = HTTPField.Name(name) {
                    fields.append(HTTPField(name: fieldName, value: value))
                }
            }
        }
        return fields
    }
}

#if !canImport(FoundationNetworking)
    /// Delivers a data task's response when its headers arrive and its body chunk by chunk.
    private final class StreamingResponseDelegate: NSObject, URLSessionDataDelegate, Sendable {
        private struct State {
            var responseContinuation: CheckedContinuation<URLResponse, any Error>?
            var metricsStored: Task<Void, Never>?
        }

        private let bodyContinuation: AsyncThrowingStream<ArraySlice<UInt8>, any Error>.Continuation
        private let state = Mutex(State())

        init(bodyContinuation: AsyncThrowingStream<ArraySlice<UInt8>, any Error>.Continuation) {
            self.bodyContinuation = bodyContinuation
        }

        func start(_ task: URLSessionDataTask, responseContinuation: CheckedContinuation<URLResponse, any Error>) {
            state.withLock { $0.responseContinuation = responseContinuation }
            task.delegate = self
            task.resume()
        }

        func urlSession(
            _: URLSession,
            dataTask _: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            takeResponseContinuation()?.resume(returning: response)
            completionHandler(.allow)
        }

        func urlSession(_: URLSession, dataTask _: URLSessionDataTask, didReceive data: Data) {
            bodyContinuation.yield(ArraySlice(data))
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didCompleteWithError error: (any Error)?) {
            takeResponseContinuation()?.resume(throwing: error ?? URLError(.badServerResponse))
            // The body ends only once its metrics are stored, so a reader of the whole body finds them.
            let metricsStored = state.withLock { $0.metricsStored }
            Task { [bodyContinuation] in
                await metricsStored?.value
                bodyContinuation.finish(throwing: error)
            }
        }

        #if canImport(TuistHAR)
            func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
                guard let transactionMetrics = metrics.transactionMetrics.last,
                      let url = task.originalRequest?.url
                else { return }
                let metricsStored = Task { await URLSessionMetricsDelegate.shared.storeMetrics(transactionMetrics, for: url) }
                state.withLock { $0.metricsStored = metricsStored }
            }
        #endif

        private func takeResponseContinuation() -> CheckedContinuation<URLResponse, any Error>? {
            state.withLock { state in
                defer { state.responseContinuation = nil }
                return state.responseContinuation
            }
        }
    }
#endif

enum TuistURLSessionTransportError: LocalizedError {
    case invalidURL(URL)
    case invalidResponse(URLResponse)

    var errorDescription: String? {
        switch self {
        case let .invalidURL(url):
            return "Invalid URL: \(url)"
        case let .invalidResponse(response):
            return "Invalid response type: \(type(of: response))"
        }
    }
}

#if canImport(TuistHAR)
    import os

    /// A per-task delegate that captures metrics for a single request.
    /// The delegate callback is guaranteed to complete before session.data() returns,
    /// so we use lock-based synchronization to safely read the metrics.
    private final class TaskMetricsDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        private let storage = OSAllocatedUnfairLock(initialState: nil as URLSessionTaskTransactionMetrics?)

        var transactionMetrics: URLSessionTaskTransactionMetrics? {
            storage.withLock { $0 }
        }

        func urlSession(_: URLSession, task _: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
            storage.withLock { $0 = metrics.transactionMetrics.last }
        }
    }
#endif
