import PathKit
import Stencil
import StencilSwiftKit
import SwiftGenKit
import TSCBasic
import TuistGraph
import TuistSupport

protocol SynthesizedResourceInterfacesGenerating {
    func render(
        parser: ResourceSynthesizer.Parser,
        parserOptions: [String: ResourceSynthesizer.Parser.Option],
        templateString: String,
        name: String,
        bundleName: String?,
        paths: [AbsolutePath]
    ) throws -> String
}

final class SynthesizedResourceInterfacesGenerator: SynthesizedResourceInterfacesGenerating {
    func render(
        parser: ResourceSynthesizer.Parser,
        parserOptions: [String: ResourceSynthesizer.Parser.Option],
        templateString: String,
        name: String,
        bundleName: String?,
        paths: [AbsolutePath]
    ) throws -> String {
        let template = Template(
            templateString: templateString,
            environment: stencilSwiftEnvironment()
        )

        let parser = try self.parser(for: parser, with: parserOptions)

        try paths.forEach { try parser.parse(path: Path($0.pathString), relativeTo: Path("")) }
        var context = parser.stencilContext()
        context = try StencilContext.enrich(
            context: context,
            parameters: makeParams(name: name, bundleName: bundleName)
        )
        return try template.render(context)
    }

    // MARK: - Helpers

    private func parser(
        for parser: ResourceSynthesizer.Parser,
        with parserOptions: [String: ResourceSynthesizer.Parser.Option]
    ) throws -> Parser {
        let options = parserOptions.mapValues(\.value)
        switch parser {
        case .assets:
            return try AssetsCatalog.Parser(options: options)
        case .strings:
            return try Strings.Parser(options: options)
        case .plists:
            return try Plist.Parser(options: options)
        case .fonts:
            return try Fonts.Parser(options: options)
        case .coreData:
            return try CoreData.Parser(options: options)
        case .interfaceBuilder:
            return try InterfaceBuilder.Parser(options: options)
        case .json:
            return try JSON.Parser(options: options)
        case .yaml:
            return try Yaml.Parser(options: options)
        case .files:
            return try Files.Parser(options: options)
        }
    }

    private func makeParams(name: String, bundleName: String?) -> [String: Any] {
        var params: [String: Any] = [:]
        params["publicAccess"] = true
        params["name"] = name
        if let bundleName {
            params["bundle"] = bundleName
        }
        return params
    }
}
