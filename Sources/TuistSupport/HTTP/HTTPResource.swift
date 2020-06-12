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
        return jsonResource(request: request, parseError: decode)
    }
  
    public static func jsonResource(request: @escaping () -> URLRequest, parseError: @escaping (Data, HTTPURLResponse) throws -> E) -> HTTPResource<T, E> {
        return HTTPResource(request: request, parse: decode, parseError: parseError)
    }
    
    private static func decode<T: Decodable>(from data: Data, _ urlResponse: HTTPURLResponse) throws -> T {
        let jsonDecoder = JSONDecoder()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        return try jsonDecoder.decode(T.self, from: data)
    }
}
