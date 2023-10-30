import ProjectDescription
import TSCBasic
import TuistGraph

extension TuistGraph.ResourceSynthesizer {
    static func from(
        manifest: ProjectDescription.ResourceSynthesizer,
        generatorPaths: GeneratorPaths,
        plugins: Plugins,
        resourceSynthesizerPathLocator: ResourceSynthesizerPathLocating
    ) throws -> Self {
        let template: TuistGraph.ResourceSynthesizer.Template
        switch manifest.templateType {
        case let .defaultTemplate(resourceName: resourceName):
            if let templatePath = resourceSynthesizerPathLocator.templatePath(
                for: resourceName,
                path: generatorPaths.manifestDirectory
            ) {
                template = .file(templatePath)
            } else {
                template = .defaultTemplate(resourceName)
            }
        case let .plugin(name: name, resourceName: resourceName):
            let path = try resourceSynthesizerPathLocator.templatePath(
                for: name,
                resourceName: resourceName,
                resourceSynthesizerPlugins: plugins.resourceSynthesizers
            )
            template = .file(path)
        }

        let parserOptions = manifest.parserOptions
            .compactMapValues { TuistGraph.ResourceSynthesizer.Parser.Option.from(manifest: $0)
            }

        return .init(
            parser: TuistGraph.ResourceSynthesizer.Parser.from(manifest: manifest.parser),
            parserOptions: parserOptions,
            extensions: manifest.extensions,
            template: template
        )
    }
}

extension TuistGraph.ResourceSynthesizer.Parser {
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

extension TuistGraph.ResourceSynthesizer.Parser.Option {
    static func from(
        manifest: ProjectDescription.ResourceSynthesizer.Parser.Option
    ) -> Self {
        switch manifest {
        case .string(let value):
            return .init(value: value)
        case .integer(let value):
            return .init(value: value)
        case .double(let value):
            return .init(value: value)
        case .boolean(let value):
            return .init(value: value)
        case .dictionary(let value):
            return .init(value: value)
        case .array(let value):
            return .init(value: value)
        }
    }
}
