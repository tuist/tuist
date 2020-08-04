import SwiftGenKit
import PathKit
import StencilSwiftKit
import TSCBasic
import TuistSupport

protocol NamespaceGenerating {
    func renderAssets(_ assetPaths: [AbsolutePath]) throws -> [(name: String, contents: String)]
}

final class NamespaceGenerator: NamespaceGenerating {
    private let resourcesNamespaceTemplatesLocator: ResourcesNamespaceTemplatesLocating
    
    init(
        resourcesNamespaceTemplatesLocator: ResourcesNamespaceTemplatesLocating = ResourcesNamespaceTemplatesLocator()
    ) {
        self.resourcesNamespaceTemplatesLocator = resourcesNamespaceTemplatesLocator
    }
    
    func renderAssets(_ assetPaths: [AbsolutePath]) throws -> [(name: String, contents: String)] {
        let templatePath = try resourcesNamespaceTemplatesLocator.locateAssetsTemplate()
        let template = StencilSwiftTemplate(
            templateString: try FileHandler.shared.readTextFile(templatePath),
            environment: stencilSwiftEnvironment()
        )
        
        return try assetPaths.map { path in
            let parser = try AssetsCatalog.Parser()
            try parser.parse(path: Path(path.pathString), relativeTo: Path(""))
            let context = parser.stencilContext()
            return (path.basenameWithoutExt, try template.render(context))
        }
    }
}
