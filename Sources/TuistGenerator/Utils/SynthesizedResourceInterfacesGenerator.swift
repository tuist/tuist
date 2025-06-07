import Path
import PathKit
import Stencil
import StencilSwiftKit
import SwiftGenKit
import TuistSupport
import XcodeGraph

protocol SynthesizedResourceInterfacesGenerating {
    func render(
        parser: ResourceSynthesizer.Parser,
        parserOptions: [String: ResourceSynthesizer.Parser.Option],
        templateString: String,
        templateParameters: [String: ResourceSynthesizer.Template.Parameter],
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
        templateParameters: [String: ResourceSynthesizer.Template.Parameter],
        name: String,
        bundleName: String?,
        paths: [AbsolutePath]
    ) throws -> String {
        let template = Template(
            templateString: templateString,
            environment: stencilSwiftEnvironment()
        )

        let parameters = makeParams(
            for: parser,
            name: name,
            bundleName: bundleName,
            userParameters: templateParameters
        )

        let parser = try self.parser(for: parser, with: parserOptions)

        try paths.forEach { try parser.parse(path: Path($0.pathString), relativeTo: Path("")) }

        var context = parser.stencilContext()
        context = try StencilContext.enrich(context: context, parameters: parameters)
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
        case .stringsCatalog:
            fatalError("WIP on: https://github.com/tuist/tuist/pull/6296")
        }
    }

    private func makeParams(
        for parser: ResourceSynthesizer.Parser,
        name: String,
        bundleName: String?,
        userParameters: [String: ResourceSynthesizer.Template.Parameter]
    ) -> [String: Any] {
        var params: [String: Any] = [:]
        params["publicAccess"] = true

        if parser == .assets || parser == .strings || parser == .fonts {
            params["name"] = name
        }

        if parser == .files || parser == .json || parser == .yaml {
            params["enumName"] = name
        }

        if parser == .files || parser == .fonts {
            if let bundleName {
                params["bundle"] = bundleName
            }
        }

        // user might want to override some default behavior (at their own risk)
        params.merge(userParameters.compactMapValues(eraseParameter)) { _, new in new }

        return params
    }

    private func eraseParameter(_ parameter: ResourceSynthesizer.Template.Parameter) -> Any {
        switch parameter {
        case let .string(value):
            return value
        case let .boolean(value):
            return value
        case let .integer(value):
            return value
        case let .double(value):
            return value
        case let .dictionary(value):
            return value.compactMapValues { eraseParameter($0) }
        case let .array(value):
            return value.compactMap { eraseParameter($0) }
        }
    }
}
