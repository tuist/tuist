import Foundation
import TuistCore

public protocol HeadersContentHashing {
    func hash(headers: Headers) throws -> String
}

/// `HeadersContentHashing`
/// is responsible for computing a hash that uniquely identifies a list of headers
public final class HeadersContentHasher: HeadersContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - HeadersContentHashing

    public func hash(headers: Headers) throws -> String {
        let allHeaders = headers.public + headers.private + headers.project
        let headersContent = try allHeaders.map { try contentHasher.hash(fileAtPath: $0) }
        return try contentHasher.hash(headersContent)
    }
}
