import Foundation
import TSCBasic
import TuistSupport

protocol LibraryMetadataProviding: PrecompiledMetadataProviding {
    /// Returns the product for the given library.
    /// - Parameter library: Library instance.
    func product(library: LibraryNode) throws -> Product
}

final class LibraryMetadataProvider: PrecompiledMetadataProvider, LibraryMetadataProviding {
    func product(library: LibraryNode) throws -> Product {
        switch try linking(binaryPath: library.path) {
        case .dynamic:
            return .dynamicLibrary
        case .static:
            return .staticLibrary
        }
    }
}
