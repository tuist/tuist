import Foundation

public struct HTTPResource<T, E: Error>: Equatable, Hashable, CustomStringConvertible {
    public let request: () -> URLRequest
    public let parse: (Data, HTTPURLResponse) throws -> T
    public let parseError: (Data, HTTPURLResponse) throws -> E

    public init(request: @escaping () -> URLRequest,
                parse: @escaping (Data, HTTPURLResponse) throws -> T,
                parseError: @escaping (Data, HTTPURLResponse) throws -> E) {
        self.request = request
        self.parse = parse
        self.parseError = parseError
    }

    public func withURL(_ url: URL) -> HTTPResource<T, E> {
        HTTPResource(request: {
            URLRequest(url: url)
        }, parse: parse,
                     parseError: parseError)
    }

    public func mappingRequest(_ requestMapper: @escaping (URLRequest) throws -> URLRequest) throws -> HTTPResource<T, E> {
        let request = try requestMapper(self.request())
        return HTTPResource(request: { request },
                            parse: parse,
                            parseError: parseError)
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
        let request = self.request()

        return "[\(request.httpMethod ?? "GET")] - \(request.url?.path ?? "")"
    }
}

extension HTTPResource where T: Decodable, E: Decodable {
    public static func jsonResource(request: @escaping () -> URLRequest) -> HTTPResource<T, E> {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase

        return HTTPResource(request: request, parse: { (data, _) -> T in
            try jsonDecoder.decode(T.self, from: data)
        }, parseError: { (data, _) -> E in
            try jsonDecoder.decode(E.self, from: data)
        })
    }
}
