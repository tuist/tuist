import PathKit
import StencilSwiftKit
import SwiftGenKit
import TSCBasic
import TuistSupport
import TuistGraph

protocol SynthesizedResourceInterfacesGenerating {
    func render(
        parser: ResourceSynthesizer.Parser,
        templateString: String,
        name: String,
        paths: [AbsolutePath]
    ) throws -> String
}

final class SynthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating {
    func render(
        parser: ResourceSynthesizer.Parser,
        templateString: String,
        name: String,
        paths: [AbsolutePath]
    ) throws -> String {
        let template = StencilSwiftTemplate(
            templateString: templateString,
            environment: stencilSwiftEnvironment()
        )
        
        let parser = try self.parser(for: parser)

        try paths.forEach { try parser.parse(path: Path($0.pathString), relativeTo: Path("")) }
        var context = parser.stencilContext()
        context = try StencilContext.enrich(
            context: context,
            parameters: [
                "publicAccess": true,
                "name": name,
            ]
        )
        return try template.render(context)
    }

    // MARK: - Helpers
    
    private func parser(for parser: ResourceSynthesizer.Parser) throws -> Parser {
        switch parser {
        case .assets:
            return try AssetsCatalog.Parser()
        case .strings:
            return try Strings.Parser()
        case .plists:
            return try Plist.Parser()
        case .fonts:
            return try Fonts.Parser()
        case .coreData:
            return try CoreData.Parser()
        case .interfaceBuilder:
            return try InterfaceBuilder.Parser()
        case .json:
            return try JSON.Parser()
        case .yaml:
            return try Yaml.Parser()
        }
    }
}
