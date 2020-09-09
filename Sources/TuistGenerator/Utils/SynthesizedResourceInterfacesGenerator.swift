import PathKit
import StencilSwiftKit
import SwiftGenKit
import TSCBasic
import TuistSupport

enum SynthesizedResourceInterfaceType {
    case assets
    case strings
    case plists
    case fonts

    var name: String {
        switch self {
        case .assets:
            return "Assets"
        case .strings:
            return "Strings"
        case .plists:
            return "Plists"
        case .fonts:
            return "Fonts"
        }
    }

    fileprivate var templateString: String {
        switch self {
        case .assets:
            return SynthesizedResourceInterfaceTemplates.assetsTemplate
        case .strings:
            return SynthesizedResourceInterfaceTemplates.stringsTemplate
        case .plists:
            return SynthesizedResourceInterfaceTemplates.plistsTemplate
        case .fonts:
            return SynthesizedResourceInterfaceTemplates.fontsTemplate
        }
    }

    fileprivate func parser() throws -> Parser {
        switch self {
        case .assets:
            return try AssetsCatalog.Parser()
        case .strings:
            return try Strings.Parser()
        case .plists:
            return try Plist.Parser()
        case .fonts:
            return try Fonts.Parser()
        }
    }
}

protocol SynthesizedResourceInterfacesGenerating {
    func render(
        _ synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType,
        name: String,
        paths: [AbsolutePath]
    ) throws -> String
}

final class SynthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating {
    func render(
        _ synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType,
        name: String,
        paths: [AbsolutePath]
    ) throws -> String {
        let template = StencilSwiftTemplate(
            templateString: synthesizedResourceInterfaceType.templateString,
            environment: stencilSwiftEnvironment()
        )

        let parser = try synthesizedResourceInterfaceType.parser()
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
}
