import Basic
import Foundation
import TuistSupport

protocol LibraryMetadataProviding: PrecompiledMetadataProviding {
    /// Returns the product for the library at the given path.
    /// - Parameter libraryPath: Path to the library.
    func product(libraryPath: AbsolutePath) throws -> Product

    /// Returns the product for the given library.
    /// - Parameter library: Library instance.
    func product(library: LibraryNode) throws -> Product
}

final class LibraryMetadataProvider: PrecompiledMetadataProvider, LibraryMetadataProviding {
    func product(libraryPath: AbsolutePath) throws -> Product {
        switch try linking(binaryPath: libraryPath) {
        case .dynamic:
            return .dynamicLibrary
        case .static:
            return .staticLibrary
        }
    }

    func product(library: LibraryNode) throws -> Product {
        return try product(libraryPath: library.path)
    }
}
