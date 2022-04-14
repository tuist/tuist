import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport

extension TuistGraph.Headers {
    /// Maps a ProjectDescription.Headers instance into a TuistGraph.Headers model.
    /// Glob patterns are resolved as part of the mapping process.
    /// - Parameters:
    ///   - manifest: Manifest representation of Headers.
    ///   - generatorPaths: Generator paths.
    ///   - productName: The name of the product.
    static func from( // swiftlint:disable:this function_body_length
        manifest: ProjectDescription.Headers,
        generatorPaths: GeneratorPaths,
        productName: String?
    ) throws -> TuistGraph.Headers {
        let resolvedUmbrellaPath = try manifest.umbrellaHeader.map { try generatorPaths.resolve(path: $0) }
        let headersFromUmbrella = try resolvedUmbrellaPath.map {
            Set(try UmbrellaHeaderHeadersExtractor.headers(from: $0, for: productName))
        }

        var autoExlcudedPaths = Set<AbsolutePath>()
        var publicHeaders: [AbsolutePath]
        let privateHeaders: [AbsolutePath]
        let projectHeaders: [AbsolutePath]

        let allowedExtensions = TuistGraph.Headers.extensions
        func unfold(
            _ list: FileList?,
            isPublic: Bool = false
        ) throws -> [AbsolutePath] {
            guard let list = list else { return [] }
            return try list.globs.flatMap {
                try $0.unfold(generatorPaths: generatorPaths) { path in
                    guard let fileExtension = path.extension,
                          allowedExtensions.contains(".\(fileExtension)"),
                          !autoExlcudedPaths.contains(path)
                    else {
                        return false
                    }
                    if isPublic, let headersFromUmbrella = headersFromUmbrella {
                        return headersFromUmbrella.contains(path.basename)
                    }
                    return true
                }
            }
        }

        switch manifest.exclusionRule {
        case .projectExcludesPrivateAndPublic:
            publicHeaders = try unfold(manifest.public, isPublic: true)
            // be sure, that umbrella was not added before
            if let resolvedUmbrellaPath = resolvedUmbrellaPath,
               !publicHeaders.contains(resolvedUmbrellaPath)
            {
                publicHeaders.append(resolvedUmbrellaPath)
            }
            autoExlcudedPaths.formUnion(publicHeaders)
            privateHeaders = try unfold(manifest.private)
            autoExlcudedPaths.formUnion(privateHeaders)
            projectHeaders = try unfold(manifest.project)

        case .publicExcludesPrivateAndProject:
            projectHeaders = try unfold(manifest.project)
            autoExlcudedPaths.formUnion(projectHeaders)
            privateHeaders = try unfold(manifest.private)
            autoExlcudedPaths.formUnion(privateHeaders)
            publicHeaders = try unfold(manifest.public, isPublic: true)
            // be sure, that umbrella was not added before
            if let resolvedUmbrellaPath = resolvedUmbrellaPath,
               !publicHeaders.contains(resolvedUmbrellaPath)
            {
                publicHeaders.append(resolvedUmbrellaPath)
            }
        }
        return Headers(public: publicHeaders, private: privateHeaders, project: projectHeaders)
    }
}
