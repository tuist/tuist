import Foundation
import Path
import ProjectDescription
import Testing
import TuistCore
import TuistSupport
import TuistTesting
import XcodeGraph
@testable import TuistLoader

func assertSettingsMatchesManifest(
    settings: XcodeGraph.Settings,
    matches manifest: ProjectDescription.Settings,
    at path: AbsolutePath,
    generatorPaths: GeneratorPaths,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(settings.base.count == manifest.base.count, sourceLocation: sourceLocation)

    let sortedConfigurations = settings.configurations.sorted { l, r -> Bool in l.key.name < r.key.name }
    let sortedManifestConfigurations = manifest.configurations.sorted(by: { $0.name.rawValue < $1.name.rawValue })
    for (configuration, manifestConfiguration) in zip(sortedConfigurations, sortedManifestConfigurations) {
        assertBuildConfigurationMatchesManifest(
            configuration: configuration,
            matches: manifestConfiguration,
            at: path,
            generatorPaths: generatorPaths,
            sourceLocation: sourceLocation
        )
    }
}

func assertTargetMatchesManifest(
    target: XcodeGraph.Target,
    matches manifest: ProjectDescription.Target,
    at _: AbsolutePath,
    generatorPaths: GeneratorPaths,
    sourceLocation: SourceLocation = #_sourceLocation
) throws {
    #expect(target.name == manifest.name, sourceLocation: sourceLocation)
    #expect(target.bundleId == manifest.bundleId, sourceLocation: sourceLocation)
    #expect(target.supportedPlatforms.count == 1, sourceLocation: sourceLocation)
    #expect(
        target.destinations.map(\.rawValue).sorted() == manifest.destinations.map(\.rawValue).sorted(),
        sourceLocation: sourceLocation
    )
    #expect(
        target.infoPlist?.path == (try generatorPaths.resolve(path: manifest.infoPlist!.path!)),
        sourceLocation: sourceLocation
    )
    #expect(
        target.entitlements?.path == (try generatorPaths.resolve(path: manifest.entitlements!.path!)),
        sourceLocation: sourceLocation
    )
    #expect(
        target.environmentVariables == manifest.environmentVariables.mapValues(EnvironmentVariable.from),
        sourceLocation: sourceLocation
    )
}

func assertBuildConfigurationMatchesManifest(
    configuration: (XcodeGraph.BuildConfiguration, XcodeGraph.Configuration?),
    matches manifest: ProjectDescription.Configuration,
    at _: AbsolutePath,
    generatorPaths: GeneratorPaths,
    sourceLocation: SourceLocation = #_sourceLocation
) {
    #expect(
        configuration.1?.settings.count == manifest.settings.count,
        sourceLocation: sourceLocation
    )
    #expect(
        configuration.1?.xcconfig == (try manifest.xcconfig.map { try generatorPaths.resolve(path: $0) }),
        sourceLocation: sourceLocation
    )
}

func coreDataModel(
    _ coreDataModel: XcodeGraph.CoreDataModel,
    matches manifest: ProjectDescription.CoreDataModel,
    at _: AbsolutePath,
    generatorPaths: GeneratorPaths
) throws -> Bool {
    coreDataModel.path == (try generatorPaths.resolve(path: manifest.path))
        && coreDataModel.currentVersion == manifest.currentVersion
}
