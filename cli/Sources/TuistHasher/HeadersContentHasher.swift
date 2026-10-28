import FileSystem
import Foundation
import Mockable
import TuistCore
import TuistSupport
import XcodeGraph

@Mockable
public protocol HeadersContentHashing {
    func hash(headers: Headers) async throws -> String
}

/// `HeadersContentHashing`
/// is responsible for computing a hash that uniquely identifies a list of headers
public struct HeadersContentHasher: HeadersContentHashing {
    static let swiftPackageLayoutVersion = "swift-package-source-headers-v2"
    private let contentHasher: ContentHashing
    private let fileSystem: FileSysteming

    // MARK: - Init

    public init(contentHasher: ContentHashing, fileSystem: FileSysteming = FileSystem()) {
        self.contentHasher = contentHasher
        self.fileSystem = fileSystem
    }

    // MARK: - HeadersContentHashing

    public func hash(headers: Headers) async throws -> String {
        let allHeaders = headers.public + headers.private + headers.project
        var headersContent = try await allHeaders.concurrentMap { try await contentHasher.hash(path: $0) }
        if let layout = headers.sourceLayout {
            // Generated SwiftPM module maps contain absolute umbrella paths. Normalize the target
            // root so identical local packages share a key across checkouts.
            let moduleMap = try await fileSystem.readTextFile(at: layout.moduleMap)
                .replacingOccurrences(of: layout.root.pathString + "/", with: "$(TUIST_PACKAGE_TARGET)/")
                .replacingOccurrences(of: "\"\(layout.root.pathString)\"", with: "\"$(TUIST_PACKAGE_TARGET)\"")
            headersContent += allHeaders.map { $0.relative(to: layout.root).pathString + "\0" }
            headersContent += [
                Self.swiftPackageLayoutVersion,
                layout.moduleName,
                layout.publicHeaders.relative(to: layout.root).pathString,
                String(layout.usesDirectoryModuleMap),
                try contentHasher.hash(moduleMap),
            ]
        }
        return try contentHasher.hash(headersContent)
    }
}
