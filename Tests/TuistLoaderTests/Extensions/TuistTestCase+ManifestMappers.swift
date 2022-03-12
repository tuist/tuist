import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistLoader

extension TuistTestCase {
    func XCTAssertSettingsMatchesManifest(
        settings: TuistGraph.Settings,
        matches manifest: ProjectDescription.Settings,
        at path: AbsolutePath,
        generatorPaths: GeneratorPaths,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(settings.base.count, manifest.base.count, file: file, line: line)

        let sortedConfigurations = settings.configurations.sorted { l, r -> Bool in l.key.name < r.key.name }
        let sortedManifestConfigurations = manifest.configurations.sorted(by: { $0.name.rawValue < $1.name.rawValue })
        for (configuration, manifestConfiguration) in zip(sortedConfigurations, sortedManifestConfigurations) {
            XCTAssertBuildConfigurationMatchesManifest(
                configuration: configuration,
                matches: manifestConfiguration,
                at: path,
                generatorPaths: generatorPaths,
                file: file,
                line: line
            )
        }
    }

    func XCTAssertTargetMatchesManifest(
        target: TuistGraph.Target,
        matches manifest: ProjectDescription.Target,
        at path: AbsolutePath,
        generatorPaths: GeneratorPaths,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(target.name, manifest.name, file: file, line: line)
        XCTAssertEqual(target.bundleId, manifest.bundleId, file: file, line: line)
        XCTAssertTrue(target.platform == manifest.platform, file: file, line: line)
        XCTAssertTrue(target.product == manifest.product, file: file, line: line)
        XCTAssertEqual(target.infoPlist?.path, try generatorPaths.resolve(path: manifest.infoPlist.path!), file: file, line: line)
        XCTAssertEqual(
            target.entitlements,
            try manifest.entitlements.map { try generatorPaths.resolve(path: $0) },
            file: file,
            line: line
        )
        XCTAssertEqual(target.environment, manifest.environment, file: file, line: line)
        try assert(
            coreDataModels: target.coreDataModels,
            matches: manifest.coreDataModels,
            at: path,
            generatorPaths: generatorPaths,
            file: file,
            line: line
        )
        try optionalAssert(target.settings, manifest.settings, file: file, line: line) {
            XCTAssertSettingsMatchesManifest(
                settings: $0,
                matches: $1,
                at: path,
                generatorPaths: generatorPaths,
                file: file,
                line: line
            )
        }
    }

    func XCTAssertBuildConfigurationMatchesManifest(
        configuration: (TuistGraph.BuildConfiguration, TuistGraph.Configuration?),
        matches manifest: ProjectDescription.Configuration,
        at _: AbsolutePath,
        generatorPaths: GeneratorPaths,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertTrue(configuration.0 == manifest, file: file, line: line)
        XCTAssertEqual(
            configuration.1?.settings.count,
            manifest.settings.count,
            file: file,
            line: line
        )
        XCTAssertEqual(
            configuration.1?.xcconfig,
            try manifest.xcconfig.map { try generatorPaths.resolve(path: $0) },
            file: file,
            line: line
        )
    }

    func assert(
        coreDataModels: [TuistGraph.CoreDataModel],
        matches manifests: [ProjectDescription.CoreDataModel],
        at path: AbsolutePath,
        generatorPaths: GeneratorPaths,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(coreDataModels.count, manifests.count, file: file, line: line)
        XCTAssertTrue(
            try coreDataModels.elementsEqual(
                manifests,
                by: { try coreDataModel($0, matches: $1, at: path, generatorPaths: generatorPaths) }
            ),
            file: file,
            line: line
        )
    }

    func coreDataModel(
        _ coreDataModel: TuistGraph.CoreDataModel,
        matches manifest: ProjectDescription.CoreDataModel,
        at _: AbsolutePath,
        generatorPaths: GeneratorPaths
    ) throws -> Bool {
        coreDataModel.path == (try generatorPaths.resolve(path: manifest.path))
            && coreDataModel.currentVersion == manifest.currentVersion
    }

    func assert(
        scheme: TuistGraph.Scheme,
        matches manifest: ProjectDescription.Scheme,
        path: AbsolutePath,
        generatorPaths: GeneratorPaths,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(scheme.name, manifest.name, file: file, line: line)
        XCTAssertEqual(scheme.shared, manifest.shared, file: file, line: line)
        try optionalAssert(scheme.buildAction, manifest.buildAction) {
            try assert(buildAction: $0, matches: $1, path: path, generatorPaths: generatorPaths, file: file, line: line)
        }

        try optionalAssert(scheme.testAction, manifest.testAction) {
            try assert(testAction: $0, matches: $1, path: path, generatorPaths: generatorPaths, file: file, line: line)
        }

        try optionalAssert(scheme.runAction, manifest.runAction) {
            try assert(runAction: $0, matches: $1, path: path, generatorPaths: generatorPaths, file: file, line: line)
        }
    }

    func assert(
        buildAction: TuistGraph.BuildAction,
        matches manifest: ProjectDescription.BuildAction,
        path _: AbsolutePath,
        generatorPaths: GeneratorPaths,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let convertedTargets: [TuistGraph.TargetReference] = try manifest.targets.map {
            let resolvedPath = try generatorPaths.resolveSchemeActionProjectPath($0.projectPath)
            return .init(projectPath: resolvedPath, name: $0.targetName)
        }
        XCTAssertEqual(buildAction.targets, convertedTargets, file: file, line: line)
    }

    func assert(
        testAction: TuistGraph.TestAction,
        matches manifest: ProjectDescription.TestAction,
        path _: AbsolutePath,
        generatorPaths: GeneratorPaths,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let targets = try manifest.targets.map { try TestableTarget.from(manifest: $0, generatorPaths: generatorPaths) }
        XCTAssertEqual(testAction.targets, targets, file: file, line: line)
        XCTAssertTrue(testAction.configurationName == manifest.configuration.rawValue, file: file, line: line)
        XCTAssertEqual(testAction.coverage, manifest.options.coverage, file: file, line: line)
        try optionalAssert(testAction.arguments, manifest.arguments) {
            assert(arguments: $0, matches: $1, file: file, line: line)
        }
    }

    func assert(
        runAction: TuistGraph.RunAction,
        matches manifest: ProjectDescription.RunAction,
        path _: AbsolutePath,
        generatorPaths: GeneratorPaths,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        XCTAssertEqual(runAction.executable?.name, manifest.executable?.targetName)
        XCTAssertEqual(
            runAction.executable?.projectPath,
            try generatorPaths.resolveSchemeActionProjectPath(manifest.executable?.projectPath),
            file: file,
            line: line
        )
        XCTAssertTrue(runAction.configurationName == manifest.configuration.rawValue, file: file, line: line)
        try optionalAssert(runAction.arguments, manifest.arguments) {
            self.assert(arguments: $0, matches: $1, file: file, line: line)
        }
    }

    func assert(
        arguments: TuistGraph.Arguments,
        matches manifest: ProjectDescription.Arguments,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        XCTAssertEqual(arguments.environment, manifest.environment, file: file, line: line)

        let rawArguments = arguments.launchArguments.reduce(into: [:]) { $0[$1.name] = $1.isEnabled }
        let rawManifest = manifest.launchArguments.reduce(into: [:]) { $0[$1.name] = $1.isEnabled }

        XCTAssertEqual(rawArguments, rawManifest, file: file, line: line)
    }

    private func optionalAssert<A, B>(
        _ optionalA: A?,
        _ optionalB: B?,
        file: StaticString = #file,
        line: UInt = #line,
        compare: (A, B) throws -> Void
    ) throws {
        switch (optionalA, optionalB) {
        case let (a?, b?):
            try compare(a, b)
        case (nil, nil):
            break
        default:
            XCTFail("mismatch of optionals", file: file, line: line)
        }
    }
}

private func == (
    _ lhs: TuistGraph.Platform,
    _ rhs: ProjectDescription.Platform
) -> Bool {
    let map: [TuistGraph.Platform: ProjectDescription.Platform] = [
        .iOS: .iOS,
        .macOS: .macOS,
        .tvOS: .tvOS,
    ]
    return map[lhs] == rhs
}

private func == (
    _ lhs: TuistGraph.Product,
    _ rhs: ProjectDescription.Product
) -> Bool {
    let map: [TuistGraph.Product: ProjectDescription.Product] = [
        .app: .app,
        .framework: .framework,
        .staticFramework: .staticFramework,
        .unitTests: .unitTests,
        .uiTests: .uiTests,
        .staticLibrary: .staticLibrary,
        .dynamicLibrary: .dynamicLibrary,
        .bundle: .bundle,
    ]
    return map[lhs] == rhs
}

private func == (
    _ lhs: BuildConfiguration,
    _ rhs: ProjectDescription.Configuration
) -> Bool {
    let map: [BuildConfiguration.Variant: ProjectDescription.Configuration.Variant] = [
        .debug: .debug,
        .release: .release,
    ]
    return map[lhs.variant] == rhs.variant && lhs.name == rhs.name.rawValue
}
