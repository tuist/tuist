import Foundation
import Mockable
import TuistCore
import XcodeGraph

@Mockable
public protocol HeadersContentHashing {
    func hash(headers: Headers) async throws -> String
}

/// `HeadersContentHashing`
/// is responsible for computing a hash that uniquely identifies a list of headers
public struct HeadersContentHasher: HeadersContentHashing {
    private let contentHasher: ContentHashing

    // MARK: - Init

    public init(contentHasher: ContentHashing) {
        self.contentHasher = contentHasher
    }

    // MARK: - HeadersContentHashing

    public func hash(headers: Headers) async throws -> String {
        let allHeaders = headers.public + headers.private + headers.project
        let headersContent = try await allHeaders.serialMap { try await contentHasher.hash(path: $0) }
        return try contentHasher.hash(headersContent)
    }
}
