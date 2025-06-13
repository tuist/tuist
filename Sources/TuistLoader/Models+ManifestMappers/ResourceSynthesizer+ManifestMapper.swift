import ProjectDescription
import TuistCore
import XcodeGraph

extension XcodeGraph.ResourceSynthesizer {
    static func from(
        manifest: ProjectDescription.ResourceSynthesizer,
        generatorPaths: GeneratorPaths,
        plugins: Plugins,
        resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating
    ) async throws -> Self {
        let template: XcodeGraph.ResourceSynthesizer.Template
        switch manifest.template {
        case let .defaultTemplate(resourceName: resourceName):
            if let templatePath = try await resourceSynthesizerPathLocator.templatePath(
                for: resourceName,
                path: generatorPaths.manifestDirectory
            ) {
                template = .file(templatePath)
            } else {
                template = .defaultTemplate(resourceName)
            }
        case let .plugin(name: name, resourceName: resourceName):
            let path = try await resourceSynthesizerPathLocator.templatePath(
                for: name,
                resourceName: resourceName,
                resourceSynthesizerPlugins: plugins.resourceSynthesizers
            )
            template = .file(path)
        }

        let parserOptions = manifest.parserOptions
            .compactMapValues {
                XcodeGraph.ResourceSynthesizer.Parser.Option.from(manifest: $0)
            }

        let templateParameters = manifest.templateParameters
            .compactMapValues {
                XcodeGraph.ResourceSynthesizer.Template.Parameter.from(manifest: $0)
            }

        return .init(
            parser: XcodeGraph.ResourceSynthesizer.Parser.from(manifest: manifest.parser),
            parserOptions: parserOptions,
            extensions: manifest.extensions,
            template: template,
            templateParameters: templateParameters
        )
    }
}

extension XcodeGraph.ResourceSynthesizer.Parser {
    static func from(
        manifest: ProjectDescription.ResourceSynthesizer.Parser
    ) -> Self {
        switch manifest {
        case .strings:
            return .strings
        case .assets:
            return .assets
        case .plists:
            return .plists
        case .fonts:
            return .fonts
        case .coreData:
            return .coreData
        case .interfaceBuilder:
            return .interfaceBuilder
        case .json:
            return .json
        case .yaml:
            return .yaml
        case .files:
            return .files
        }
    }
}

extension XcodeGraph.ResourceSynthesizer.Template.Parameter {
    static func from(
        manifest: ProjectDescription.ResourceSynthesizer.Template.Parameter
    ) -> Self {
        switch manifest {
        case let .string(value):
            return .string(value)
        case let .integer(value):
            return .integer(value)
        case let .double(value):
            return .double(value)
        case let .boolean(value):
            return .boolean(value)
        case let .dictionary(value):
            return .dictionary(value.mapValues { Self.from(manifest: $0) })
        case let .array(value):
            return .array(value.map { Self.from(manifest: $0) })
        }
    }
}

extension XcodeGraph.ResourceSynthesizer.Parser.Option {
    static func from(
        manifest: ProjectDescription.ResourceSynthesizer.Parser.Option
    ) -> Self {
        switch manifest {
        case let .string(value):
            return .init(value: value)
        case let .integer(value):
            return .init(value: value)
        case let .double(value):
            return .init(value: value)
        case let .boolean(value):
            return .init(value: value)
        case let .dictionary(value):
            return .init(value: value)
        case let .array(value):
            return .init(value: value)
        }
    }
}
