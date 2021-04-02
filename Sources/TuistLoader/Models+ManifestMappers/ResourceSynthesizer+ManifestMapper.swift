import ProjectDescription
import TSCBasic
import TuistGraph

extension TuistGraph.ResourceSynthesizer {
    static func from(
        manifest: ProjectDescription.ResourceSynthesizer,
        generatorPaths: GeneratorPaths,
        plugins: Plugins,
        pluginsHelper: PluginsHelping
    ) throws -> Self {
        let template: TuistGraph.ResourceSynthesizer.Template
        switch manifest.templateType {
        case let .defaultTemplate(resourceName: resourceName):
            template = .defaultTemplate(resourceName)
        case let .file(path):
            let path = try generatorPaths.resolve(path: path)
            template = .file(path)
        case let .plugin(name: name, resourceName: resourceName):
            let path = try pluginsHelper.templatePath(
                for: name,
                resourceName: resourceName,
                resourceSynthesizerPlugins: plugins.resourceSynthesizers
            )
            template = .file(path)
        }
        return .init(
            parser: TuistGraph.ResourceSynthesizer.Parser.from(manifest: manifest.parser),
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
        }
    }
}
