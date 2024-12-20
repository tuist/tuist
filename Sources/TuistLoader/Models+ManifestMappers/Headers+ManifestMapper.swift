import FileSystem
import Foundation
import Path
import ProjectDescription
import TuistCore
import TuistSupport
import XcodeGraph

extension XcodeGraph.Headers {
    /// Maps a ProjectDescription.Headers instance into a XcodeGraph.Headers model.
    /// Glob patterns are resolved as part of the mapping process.
    /// - Parameters:
    ///   - manifest: Manifest representation of Headers.
    ///   - generatorPaths: Generator paths.
    ///   - productName: The name of the product.
    static func from( // swiftlint:disable:this function_body_length
        manifest: ProjectDescription.Headers,
        generatorPaths: GeneratorPaths,
        productName: String?,
        fileSystem: FileSysteming
    ) async throws -> XcodeGraph.Headers {
        let resolvedUmbrellaPath = try manifest.umbrellaHeader.map { try generatorPaths.resolve(path: $0) }
        let headersFromUmbrella = try resolvedUmbrellaPath.map {
            Set(try UmbrellaHeaderHeadersExtractor.headers(from: $0, for: productName))
        }

        var autoExlcudedPaths = Set<AbsolutePath>()
        var publicHeaders: [AbsolutePath]
        let privateHeaders: [AbsolutePath]
        let projectHeaders: [AbsolutePath]

        let allowedExtensions = XcodeGraph.Headers.extensions
        func unfold(
            _ list: FileList?,
            isPublic: Bool = false
        ) async throws -> [AbsolutePath] {
            guard let list else { return [] }
            return try await list.globs.concurrentFlatMap {
                try await $0.unfold(generatorPaths: generatorPaths, fileSystem: fileSystem) { path in
                    guard let fileExtension = path.extension,
                          allowedExtensions.contains(".\(fileExtension)"),
                          !autoExlcudedPaths.contains(path)
                    else {
                        return false
                    }
                    if isPublic, let headersFromUmbrella {
                        return headersFromUmbrella.contains(path.basename)
                    }
                    return true
                }
            }
        }

        switch manifest.exclusionRule {
        case .projectExcludesPrivateAndPublic:
            publicHeaders = try await unfold(manifest.public, isPublic: true)
            // be sure, that umbrella was not added before
            if let resolvedUmbrellaPath,
               !publicHeaders.contains(resolvedUmbrellaPath)
            {
                publicHeaders.append(resolvedUmbrellaPath)
            }
            autoExlcudedPaths.formUnion(publicHeaders)
            privateHeaders = try await unfold(manifest.private)
            autoExlcudedPaths.formUnion(privateHeaders)
            projectHeaders = try await unfold(manifest.project)

        case .publicExcludesPrivateAndProject:
            projectHeaders = try await unfold(manifest.project)
            autoExlcudedPaths.formUnion(projectHeaders)
            privateHeaders = try await unfold(manifest.private)
            autoExlcudedPaths.formUnion(privateHeaders)
            publicHeaders = try await unfold(manifest.public, isPublic: true)
            // be sure, that umbrella was not added before
            if let resolvedUmbrellaPath,
               !publicHeaders.contains(resolvedUmbrellaPath)
            {
                publicHeaders.append(resolvedUmbrellaPath)
            }
        }
        return Headers(
            public: publicHeaders.sorted(),
            private: privateHeaders.sorted(),
            project: projectHeaders.sorted()
        )
    }
}
