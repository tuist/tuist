import Foundation
import TSCBasic
@testable import TuistCore

public final class MockLibraryMetadataProvider: MockPrecompiledMetadataProvider, LibraryMetadataProviding {
    public var productStub: ((LibraryNode) throws -> Product)?
    public func product(library: LibraryNode) throws -> Product {
        if let productStub = productStub {
            return try productStub(library)
        } else {
            return .staticLibrary
        }
    }
}
