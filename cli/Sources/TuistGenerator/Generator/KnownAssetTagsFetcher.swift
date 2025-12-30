import Foundation
import PathKit
import XcodeGraph

private struct ContentJson: Decodable {
    struct ContentProperties: Decodable {
        enum CodingKeys: String, CodingKey {
            case onDemandResourceTags = "on-demand-resource-tags"
        }

        let onDemandResourceTags: [String]
    }

    let properties: ContentProperties
}

protocol KnownAssetTagsFetching: AnyObject {
    func fetch(project: Project) throws -> [String]
}

final class KnownAssetTagsFetcher: KnownAssetTagsFetching {
    func fetch(project: Project) throws -> [String] {
        var tags = project.targets.values.map { $0.resources.resources.map(\.tags).flatMap { $0 } }.flatMap { $0 }

        let initialInstallTags = project.targets.values.compactMap {
            $0.onDemandResourcesTags?.initialInstall?.compactMap { $0 }
        }.flatMap { $0 }

        let prefetchOrderTags = project.targets.values.compactMap {
            $0.onDemandResourcesTags?.prefetchOrder?.compactMap { $0 }
        }.flatMap { $0 }

        tags.append(contentsOf: initialInstallTags)
        tags.append(contentsOf: prefetchOrderTags)

        var assetContentsPaths: Set<Path> = []
        let decoder = JSONDecoder()
        for target in project.targets.values {
            let assetCatalogs = target.resources.resources.filter { $0.path.extension == "xcassets" }
            for assetCatalog in assetCatalogs {
                guard let children = try? assetCatalog.path.path.recursiveChildren() else { continue }
                let contents = children.filter { $0.lastComponent == "Contents.json" }
                for content in contents {
                    assetContentsPaths.insert(content)
                }
            }
        }

        var assetsTags: [String] = []
        for path in assetContentsPaths {
            guard let data = try? Data(contentsOf: path.url) else { continue }
            guard let attributes = try? decoder.decode(ContentJson.self, from: data) else { continue }
            assetsTags.append(contentsOf: attributes.properties.onDemandResourceTags)
        }

        tags.append(contentsOf: assetsTags)

        let uniqueTags = Set(tags).sorted()

        return uniqueTags
    }
}
