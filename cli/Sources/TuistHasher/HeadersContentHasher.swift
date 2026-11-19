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
    static let swiftPackageLayoutVersion = "swift-package-source-headers-v3"
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
            headersContent += Self.swiftPackageLayoutInputs(headers: headers, layout: layout)
            headersContent.append(try contentHasher.hash(moduleMap))
        }
        return try contentHasher.hash(headersContent)
    }

    /// How a SwiftPM target's headers are packaged in its cached artifact.
    static func swiftPackageLayoutInputs(headers: Headers, layout: Headers.SourceLayout) -> [String] {
        var inputs = [
            swiftPackageLayoutVersion,
            layout.moduleName,
            layout.publicHeaders.relative(to: layout.root).pathString,
            String(layout.usesDirectoryModuleMap),
        ]
        // Frameworks now keep an `include/<Module>/` namespace in Headers. Only these targets' keys change, so
        // artifacts exported before that are not reused and other packages keep theirs.
        let allHeaders = headers.public + headers.private + headers.project
        let namespace = layout.publicHeaders.appending(component: layout.moduleName)
        if !layout.usesDirectoryModuleMap, allHeaders.contains(where: { $0.isDescendant(of: namespace) }) {
            inputs.append("framework-headers-namespace")
        }
        // Textually included files such as `.inl` were left out of artifacts before, so their targets' keys change.
        if allHeaders.contains(where: { ["inl", "inc", "tcc", "tpp"].contains($0.extension ?? "") }) {
            inputs.append("textual-headers")
        }
        return inputs
    }
}
