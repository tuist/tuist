import Foundation

/// HTTP Archive (HAR) 1.2 format representation.
/// Based on the W3C specification: https://w3c.github.io/web-performance/specs/HAR/Overview.html
public enum HAR {
    /// The root object of a HAR file.
    public struct Log: Codable, Sendable, Equatable {
        public var version: String
        public var creator: Creator
        public var browser: Browser?
        public var pages: [Page]?
        public var entries: [Entry]
        public var comment: String?

        public init(
            version: String = "1.2",
            creator: Creator,
            browser: Browser? = nil,
            pages: [Page]? = nil,
            entries: [Entry] = [],
            comment: String? = nil
        ) {
            self.version = version
            self.creator = creator
            self.browser = browser
            self.pages = pages
            self.entries = entries
            self.comment = comment
        }
    }

    /// Information about the application that created the HAR file.
    public struct Creator: Codable, Sendable, Equatable {
        public var name: String
        public var version: String
        public var comment: String?

        public init(name: String, version: String, comment: String? = nil) {
            self.name = name
            self.version = version
            self.comment = comment
        }
    }

    /// Information about the browser that created the HAR file.
    public struct Browser: Codable, Sendable, Equatable {
        public var name: String
        public var version: String
        public var comment: String?

        public init(name: String, version: String, comment: String? = nil) {
            self.name = name
            self.version = version
            self.comment = comment
        }
    }

    /// Represents a page within the HAR file.
    public struct Page: Codable, Sendable, Equatable {
        public var startedDateTime: Date
        public var id: String
        public var title: String
        public var pageTimings: PageTimings
        public var comment: String?

        public init(
            startedDateTime: Date,
            id: String,
            title: String,
            pageTimings: PageTimings,
            comment: String? = nil
        ) {
            self.startedDateTime = startedDateTime
            self.id = id
            self.title = title
            self.pageTimings = pageTimings
            self.comment = comment
        }
    }

    /// Timing information for a page.
    public struct PageTimings: Codable, Sendable, Equatable {
        public var onContentLoad: Int?
        public var onLoad: Int?
        public var comment: String?

        public init(onContentLoad: Int? = nil, onLoad: Int? = nil, comment: String? = nil) {
            self.onContentLoad = onContentLoad
            self.onLoad = onLoad
            self.comment = comment
        }
    }

    /// Represents a single HTTP request/response pair.
    public struct Entry: Codable, Sendable, Equatable {
        public var startedDateTime: Date
        public var time: Int
        public var request: Request
        public var response: Response
        public var cache: Cache
        public var timings: Timings
        public var serverIPAddress: String?
        public var connection: String?
        public var comment: String?

        public init(
            startedDateTime: Date,
            time: Int,
            request: Request,
            response: Response,
            cache: Cache = Cache(),
            timings: Timings,
            serverIPAddress: String? = nil,
            connection: String? = nil,
            comment: String? = nil
        ) {
            self.startedDateTime = startedDateTime
            self.time = time
            self.request = request
            self.response = response
            self.cache = cache
            self.timings = timings
            self.serverIPAddress = serverIPAddress
            self.connection = connection
            self.comment = comment
        }
    }

    /// HTTP request information.
    public struct Request: Codable, Sendable, Equatable {
        public var method: String
        public var url: String
        public var httpVersion: String
        public var cookies: [Cookie]
        public var headers: [Header]
        public var queryString: [QueryParameter]
        public var postData: PostData?
        public var headersSize: Int
        public var bodySize: Int
        public var comment: String?

        public init(
            method: String,
            url: String,
            httpVersion: String = "HTTP/1.1",
            cookies: [Cookie] = [],
            headers: [Header] = [],
            queryString: [QueryParameter] = [],
            postData: PostData? = nil,
            headersSize: Int = -1,
            bodySize: Int = 0,
            comment: String? = nil
        ) {
            self.method = method
            self.url = url
            self.httpVersion = httpVersion
            self.cookies = cookies
            self.headers = headers
            self.queryString = queryString
            self.postData = postData
            self.headersSize = headersSize
            self.bodySize = bodySize
            self.comment = comment
        }
    }

    /// HTTP response information.
    public struct Response: Codable, Sendable, Equatable {
        public var status: Int
        public var statusText: String
        public var httpVersion: String
        public var cookies: [Cookie]
        public var headers: [Header]
        public var content: Content
        public var redirectURL: String
        public var headersSize: Int
        public var bodySize: Int
        public var comment: String?

        public init(
            status: Int,
            statusText: String,
            httpVersion: String = "HTTP/1.1",
            cookies: [Cookie] = [],
            headers: [Header] = [],
            content: Content,
            redirectURL: String = "",
            headersSize: Int = -1,
            bodySize: Int = 0,
            comment: String? = nil
        ) {
            self.status = status
            self.statusText = statusText
            self.httpVersion = httpVersion
            self.cookies = cookies
            self.headers = headers
            self.content = content
            self.redirectURL = redirectURL
            self.headersSize = headersSize
            self.bodySize = bodySize
            self.comment = comment
        }
    }

    /// HTTP cookie information.
    public struct Cookie: Codable, Sendable, Equatable {
        public var name: String
        public var value: String
        public var path: String?
        public var domain: String?
        public var expires: Date?
        public var httpOnly: Bool?
        public var secure: Bool?
        public var comment: String?

        public init(
            name: String,
            value: String,
            path: String? = nil,
            domain: String? = nil,
            expires: Date? = nil,
            httpOnly: Bool? = nil,
            secure: Bool? = nil,
            comment: String? = nil
        ) {
            self.name = name
            self.value = value
            self.path = path
            self.domain = domain
            self.expires = expires
            self.httpOnly = httpOnly
            self.secure = secure
            self.comment = comment
        }
    }

    /// HTTP header information.
    public struct Header: Codable, Sendable, Equatable {
        public var name: String
        public var value: String
        public var comment: String?

        public init(name: String, value: String, comment: String? = nil) {
            self.name = name
            self.value = value
            self.comment = comment
        }
    }

    /// Query string parameter.
    public struct QueryParameter: Codable, Sendable, Equatable {
        public var name: String
        public var value: String
        public var comment: String?

        public init(name: String, value: String, comment: String? = nil) {
            self.name = name
            self.value = value
            self.comment = comment
        }
    }

    /// POST data information.
    public struct PostData: Codable, Sendable, Equatable {
        public var mimeType: String
        public var params: [Param]?
        public var text: String?
        public var comment: String?

        public init(
            mimeType: String,
            params: [Param]? = nil,
            text: String? = nil,
            comment: String? = nil
        ) {
            self.mimeType = mimeType
            self.params = params
            self.text = text
            self.comment = comment
        }
    }

    /// POST data parameter.
    public struct Param: Codable, Sendable, Equatable {
        public var name: String
        public var value: String?
        public var fileName: String?
        public var contentType: String?
        public var comment: String?

        public init(
            name: String,
            value: String? = nil,
            fileName: String? = nil,
            contentType: String? = nil,
            comment: String? = nil
        ) {
            self.name = name
            self.value = value
            self.fileName = fileName
            self.contentType = contentType
            self.comment = comment
        }
    }

    /// Response content information.
    public struct Content: Codable, Sendable, Equatable {
        public var size: Int
        public var compression: Int?
        public var mimeType: String
        public var text: String?
        public var encoding: String?
        public var comment: String?

        public init(
            size: Int,
            compression: Int? = nil,
            mimeType: String,
            text: String? = nil,
            encoding: String? = nil,
            comment: String? = nil
        ) {
            self.size = size
            self.compression = compression
            self.mimeType = mimeType
            self.text = text
            self.encoding = encoding
            self.comment = comment
        }
    }

    /// Cache information (before and after the request).
    public struct Cache: Codable, Sendable, Equatable {
        public var beforeRequest: CacheState?
        public var afterRequest: CacheState?
        public var comment: String?

        public init(
            beforeRequest: CacheState? = nil,
            afterRequest: CacheState? = nil,
            comment: String? = nil
        ) {
            self.beforeRequest = beforeRequest
            self.afterRequest = afterRequest
            self.comment = comment
        }
    }

    /// Cache state information.
    public struct CacheState: Codable, Sendable, Equatable {
        public var expires: Date?
        public var lastAccess: Date?
        public var eTag: String?
        public var hitCount: Int?
        public var comment: String?

        public init(
            expires: Date? = nil,
            lastAccess: Date? = nil,
            eTag: String? = nil,
            hitCount: Int? = nil,
            comment: String? = nil
        ) {
            self.expires = expires
            self.lastAccess = lastAccess
            self.eTag = eTag
            self.hitCount = hitCount
            self.comment = comment
        }
    }

    /// Timing information for the request/response.
    public struct Timings: Codable, Sendable, Equatable {
        public var blocked: Int?
        public var dns: Int?
        public var connect: Int?
        public var send: Int
        public var wait: Int
        public var receive: Int
        public var ssl: Int?
        public var comment: String?

        public init(
            blocked: Int? = nil,
            dns: Int? = nil,
            connect: Int? = nil,
            send: Int = 0,
            wait: Int = 0,
            receive: Int = 0,
            ssl: Int? = nil,
            comment: String? = nil
        ) {
            self.blocked = blocked
            self.dns = dns
            self.connect = connect
            self.send = send
            self.wait = wait
            self.receive = receive
            self.ssl = ssl
            self.comment = comment
        }
    }
}

// MARK: - JSON Encoding/Decoding

extension HAR {
    /// Custom date formatter for HAR format (ISO 8601 with fractional seconds).
    public static var dateFormatter: ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }

    /// Encodes a HAR log to JSON data.
    public static func encode(_ log: Log) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(dateFormatter.string(from: date))
        }
        return try encoder.encode(["log": log])
    }

    /// Decodes a HAR log from JSON data.
    public static func decode(from data: Data) throws -> Log {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = dateFormatter.date(from: dateString) {
                return date
            }
            let fallbackFormatter = ISO8601DateFormatter()
            if let date = fallbackFormatter.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Cannot decode date string \(dateString)"
            )
        }
        let wrapper = try decoder.decode([String: Log].self, from: data)
        guard let log = wrapper["log"] else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: [],
                    debugDescription: "Missing 'log' key in HAR file"
                )
            )
        }
        return log
    }

    /// Saves a HAR log to a file.
    public static func save(_ log: Log, to url: URL) throws {
        let data = try encode(log)
        try data.write(to: url)
    }

    /// Loads a HAR log from a file.
    public static func load(from url: URL) throws -> Log {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}
