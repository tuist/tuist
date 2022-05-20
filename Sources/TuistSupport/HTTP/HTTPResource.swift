import Foundation

public struct HTTPResource<T, E: Error>: Equatable, Hashable, CustomStringConvertible {
    public let request: () -> URLRequest
    public let parse: (Data, HTTPURLResponse) throws -> T
    public let parseError: (Data, HTTPURLResponse) throws -> E

    public init(
        request: @escaping () -> URLRequest,
        parse: @escaping (Data, HTTPURLResponse) throws -> T,
        parseError: @escaping (Data, HTTPURLResponse) throws -> E
    ) {
        self.request = request
        self.parse = parse
        self.parseError = parseError
    }

    public func withURL(_ url: URL) -> HTTPResource<T, E> {
        HTTPResource(request: {
            URLRequest(url: url)
        }, parse: parse, parseError: parseError)
    }

    public func mappingRequest(_ requestMapper: @escaping (URLRequest) throws -> URLRequest) throws -> HTTPResource<T, E> {
        let request = try requestMapper(request())
        return HTTPResource(
            request: { request },
            parse: parse,
            parseError: parseError
        )
    }

    public func eraseToAnyResource() -> HTTPResource<Any, Error> {
        HTTPResource<Any, Error> {
            self.request()
        } parse: { data, response in
            try self.parse(data, response) as Any
        } parseError: { data, response in
            try self.parseError(data, response)
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(request())
    }

    // MARK: - Equatable

    public static func == (lhs: HTTPResource, rhs: HTTPResource) -> Bool {
        lhs.request() == rhs.request()
    }

    // MARK: - CustomStringConvertible

    public var description: String {
        let request = request()

        return "[\(request.httpMethod ?? "GET")] - \(request.url?.path ?? "")"
    }
}

extension HTTPResource where T: Decodable, E: Decodable {
    public static func jsonResource(request: @escaping () -> URLRequest) -> HTTPResource<T, E> {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return HTTPResource<T, E>(
            request: request,
            parse: { data, _ in
                try jsonDecoder.decode(T.self, from: data)
            },
            parseError: { data, _ in try jsonDecoder.decode(E.self, from: data) }
        )
    }

    public static func jsonResource(for url: URL, httpMethod: String) -> HTTPResource<T, E> {
        var request = URLRequest(url: url)
        request.httpMethod = httpMethod
        return .jsonResource { request }
    }
}
