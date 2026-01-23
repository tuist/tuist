import Foundation
import HTTPTypes
import OpenAPIRuntime

/// A custom URLSession transport that uses async/await APIs to enable metrics collection.
/// Unlike the default URLSessionTransport which uses completion handlers, this transport
/// uses `data(for:delegate:)` which triggers the URLSessionTaskDelegate methods including
/// `didFinishCollecting` for capturing detailed timing metrics.
public struct TuistURLSessionTransport: ClientTransport {
    private let session: URLSession

    public init(session: URLSession = .tuistShared) {
        self.session = session
    }

    public func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID _: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        let urlRequest = try buildURLRequest(from: request, body: body, baseURL: baseURL)

        let (data, response) = try await session.data(for: urlRequest, delegate: nil)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw TuistURLSessionTransportError.invalidResponse(response)
        }

        let responseHeaders = buildHTTPFields(from: httpResponse)
        let httpResponseObj = HTTPResponse(status: .init(code: httpResponse.statusCode), headerFields: responseHeaders)

        let responseBody: HTTPBody? = data.isEmpty ? nil : HTTPBody(data)

        return (httpResponseObj, responseBody)
    }

    private func buildURLRequest(from request: HTTPRequest, body: HTTPBody?, baseURL: URL) throws -> URLRequest {
        let url = try buildURL(baseURL: baseURL, path: request.path)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue

        for field in request.headerFields {
            urlRequest.setValue(field.value, forHTTPHeaderField: field.name.rawName)
        }

        if let body {
            urlRequest.httpBody = try collectBodySync(body)
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

    private func collectBodySync(_ body: HTTPBody) throws -> Data? {
        switch body.length {
        case .unknown:
            return nil
        case let .known(length):
            var data = Data()
            data.reserveCapacity(Int(length))
            let semaphore = DispatchSemaphore(value: 0)
            var collectedData: Data?
            var collectionError: Error?

            Task {
                do {
                    collectedData = try await Data(collecting: body, upTo: Int(length))
                } catch {
                    collectionError = error
                }
                semaphore.signal()
            }

            semaphore.wait()

            if let error = collectionError {
                throw error
            }

            return collectedData
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
