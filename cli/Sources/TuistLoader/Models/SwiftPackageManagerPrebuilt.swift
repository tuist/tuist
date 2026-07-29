import Foundation
import Path

public struct SwiftPackageManagerPrebuilt: Equatable, Hashable, Sendable {
    public let identity: String
    public let version: String
    public let libraryName: String
    public let path: AbsolutePath
    public let checkoutPath: AbsolutePath?
    public let products: [String]
    public let includePath: [RelativePath]?
    public let cModules: [String]

    public init(
        identity: String,
        version: String,
        libraryName: String,
        path: AbsolutePath,
        checkoutPath: AbsolutePath?,
        products: [String],
        includePath: [RelativePath]?,
        cModules: [String]
    ) {
        self.identity = identity
        self.version = version
        self.libraryName = libraryName
        self.path = path
        self.checkoutPath = checkoutPath
        self.products = products
        self.includePath = includePath
        self.cModules = cModules
    }
}
