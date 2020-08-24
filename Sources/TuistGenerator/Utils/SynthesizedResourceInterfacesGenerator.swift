import PathKit
import StencilSwiftKit
import SwiftGenKit
import TSCBasic
import TuistSupport

enum SynthesizedResourceInterfaceType {
    case assets
    case strings
    
    var templateFileName: String {
        switch self {
        case .assets:
            return "xcassets.stencil"
        case .strings:
            return "strings.stencil"
        }
    }
    
    fileprivate func parser() throws -> Parser {
        switch self {
        case .assets:
            return try AssetsCatalog.Parser()
        case .strings:
            return try Strings.Parser()
        }
    }
}

protocol SynthesizedResourceInterfacesGenerating {
    func render(
        _ namespaceType: SynthesizedResourceInterfaceType,
        name: String,
        paths: [AbsolutePath]
    ) throws -> [(name: String, contents: String)]
}

final class SynthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating {
    private let synthesizedResourceInterfaceTemplatesLocator: SynthesizedResourceInterfaceTemplatesLocating
    
    init(
        synthesizedResourceInterfaceTemplatesLocator: SynthesizedResourceInterfaceTemplatesLocating = SynthesizedResourceInterfaceTemplatesLocator()
    ) {
        self.synthesizedResourceInterfaceTemplatesLocator = synthesizedResourceInterfaceTemplatesLocator
    }
    
    func render(
        _ synthesizedResourceInterfaceType: SynthesizedResourceInterfaceType,
        name: String,
        paths: [AbsolutePath]
    ) throws -> [(name: String, contents: String)] {
        let templatePath = try synthesizedResourceInterfaceTemplatesLocator.locateTemplate(for: synthesizedResourceInterfaceType)
        let template = StencilSwiftTemplate(
            templateString: try FileHandler.shared.readTextFile(templatePath),
            environment: stencilSwiftEnvironment()
        )
        
        return try paths.map { path in
            let parser = try synthesizedResourceInterfaceType.parser()
            try parser.parse(path: Path(path.pathString), relativeTo: Path(""))
            var context = parser.stencilContext()
            context = try StencilContext.enrich(
                context: context,
                parameters: [
                    "publicAccess": true,
                    "name": name
                ]
            )
            return (path.basenameWithoutExt, try template.render(context))
        }
    }
}

//{% set enumName %}{{param.enumName|default:"Asset"}}{% endset %}
//{% set arResourceGroupType %}{{param.arResourceGroupTypeName|default:"ARResourceGroupAsset"}}{% endset %}
//{% set colorType %}{{param.colorTypeName|default:"ColorAsset"}}{% endset %}
//{% set dataType %}{{param.dataTypeName|default:"DataAsset"}}{% endset %}
//{% set imageType %}{{param.imageTypeName|default:"ImageAsset"}}{% endset %}
