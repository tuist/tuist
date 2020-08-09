import SwiftGenKit
import PathKit
import StencilSwiftKit
import TSCBasic
import TuistSupport

enum NamespaceType {
    case assets
    
    var templateFileName: String {
        switch self {
        case .assets:
            return "xcassets.stencil"
        }
    }
}

private extension NamespaceType {
    func parser() throws -> Parser {
        switch self {
        case .assets:
            return try AssetsCatalog.Parser()
        }
    }
}

protocol NamespaceGenerating {
    func render(_ namespaceType: NamespaceType, paths: [AbsolutePath]) throws -> [(name: String, contents: String)]
}

final class NamespaceGenerator: NamespaceGenerating {
    private let resourcesNamespaceTemplatesLocator: ResourcesNamespaceTemplatesLocating
    
    init(
        resourcesNamespaceTemplatesLocator: ResourcesNamespaceTemplatesLocating = ResourcesNamespaceTemplatesLocator()
    ) {
        self.resourcesNamespaceTemplatesLocator = resourcesNamespaceTemplatesLocator
    }
    
    func render(_ namespaceType: NamespaceType, paths: [AbsolutePath]) throws -> [(name: String, contents: String)] {
        let templatePath = try resourcesNamespaceTemplatesLocator.locateTemplate(for: namespaceType)
        let template = StencilSwiftTemplate(
            templateString: try FileHandler.shared.readTextFile(templatePath),
            environment: stencilSwiftEnvironment()
        )
        
        return try paths.map { path in
            let parser = try namespaceType.parser()
            try parser.parse(path: Path(path.pathString), relativeTo: Path(""))
            let context = parser.stencilContext()
            return (path.basenameWithoutExt, try template.render(context))
        }
    }
}
