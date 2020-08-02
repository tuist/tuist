import Foundation
import ProjectDescription
import TSCBasic
import TuistCore
import TuistSupport
import TuistSupportTesting
import XCTest
@testable import TuistLoader

extension TuistTestCase {
    func XCTAssertSettingsMatchesManifest(settings: TuistCore.Settings,
                                          matches manifest: ProjectDescription.Settings,
                                          at path: AbsolutePath,
                                          generatorPaths: GeneratorPaths,
                                          file: StaticString = #file,
                                          line: UInt = #line)
    {
        XCTAssertEqual(settings.base.count, manifest.base.count, file: file, line: line)

        let sortedConfigurations = settings.configurations.sorted { (l, r) -> Bool in l.key.name < r.key.name }
        let sortedManifsetConfigurations = manifest.configurations.sorted(by: { $0.name < $1.name })
        for (configuration, manifestConfiguration) in zip(sortedConfigurations, sortedManifsetConfigurations) {
            XCTAssertBuildConfigurationMatchesManifest(configuration: configuration, matches: manifestConfiguration, at: path, generatorPaths: generatorPaths, file: file, line: line)
        }
    }

    func XCTAssertTargetMatchesManifest(target: TuistCore.Target,
                                        matches manifest: ProjectDescription.Target,
                                        at path: AbsolutePath,
                                        generatorPaths: GeneratorPaths,
                                        file: StaticString = #file,
                                        line: UInt = #line) throws
    {
        XCTAssertEqual(target.name, manifest.name, file: file, line: line)
        XCTAssertEqual(target.bundleId, manifest.bundleId, file: file, line: line)
        XCTAssertTrue(target.platform == manifest.platform, file: file, line: line)
        XCTAssertTrue(target.product == manifest.product, file: file, line: line)
        XCTAssertEqual(target.infoPlist?.path, try generatorPaths.resolve(path: manifest.infoPlist.path!), file: file, line: line)
        XCTAssertEqual(target.entitlements, try manifest.entitlements.map { try generatorPaths.resolve(path: $0) }, file: file, line: line)
        XCTAssertEqual(target.environment, manifest.environment, file: file, line: line)
        try assert(coreDataModels: target.coreDataModels, matches: manifest.coreDataModels, at: path, generatorPaths: generatorPaths, file: file, line: line)
        try optionalAssert(target.settings, manifest.settings, file: file, line: line) {
            XCTAssertSettingsMatchesManifest(settings: $0, matches: $1, at: path, generatorPaths: generatorPaths, file: file, line: line)
        }
    }

    func XCTAssertBuildConfigurationMatchesManifest(configuration: (TuistCore.BuildConfiguration, TuistCore.Configuration?),
                                                    matches manifest: ProjectDescription.CustomConfiguration,
                                                    at _: AbsolutePath,
                                                    generatorPaths: GeneratorPaths,
                                                    file: StaticString = #file,
                                                    line: UInt = #line)
    {
        XCTAssertTrue(configuration.0 == manifest, file: file, line: line)
        XCTAssertEqual(configuration.1?.settings.count,
                       manifest.configuration?.settings.count,
                       file: file, line: line)
        XCTAssertEqual(configuration.1?.xcconfig,
                       try manifest.configuration?.xcconfig.map { try generatorPaths.resolve(path: $0) },
                       file: file, line: line)
    }

    func assert(coreDataModels: [TuistCore.CoreDataModel],
                matches manifests: [ProjectDescription.CoreDataModel],
                at path: AbsolutePath,
                generatorPaths: GeneratorPaths,
                file: StaticString = #file,
                line: UInt = #line) throws
    {
        XCTAssertEqual(coreDataModels.count, manifests.count, file: file, line: line)
        XCTAssertTrue(try coreDataModels.elementsEqual(manifests, by: { try coreDataModel($0, matches: $1, at: path, generatorPaths: generatorPaths) }),
                      file: file,
                      line: line)
    }

    func coreDataModel(_ coreDataModel: TuistCore.CoreDataModel,
                       matches manifest: ProjectDescription.CoreDataModel,
                       at _: AbsolutePath,
                       generatorPaths: GeneratorPaths) throws -> Bool
    {
        coreDataModel.path == (try generatorPaths.resolve(path: manifest.path))
            && coreDataModel.currentVersion == manifest.currentVersion
    }

    func assert(scheme: TuistCore.Scheme,
                matches manifest: ProjectDescription.Scheme,
                path: AbsolutePath,
                generatorPaths: GeneratorPaths,
                file: StaticString = #file,
                line: UInt = #line) throws
    {
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

    func assert(buildAction: TuistCore.BuildAction,
                matches manifest: ProjectDescription.BuildAction,
                path _: AbsolutePath,
                generatorPaths: GeneratorPaths,
                file: StaticString = #file,
                line: UInt = #line) throws
    {
        let convertedTargets: [TuistCore.TargetReference] = try manifest.targets.map {
            let resolvedPath = try generatorPaths.resolveSchemeActionProjectPath($0.projectPath)
            return .init(projectPath: resolvedPath, name: $0.targetName)
        }
        XCTAssertEqual(buildAction.targets, convertedTargets, file: file, line: line)
    }

    func assert(testAction: TuistCore.TestAction,
                matches manifest: ProjectDescription.TestAction,
                path _: AbsolutePath,
                generatorPaths: GeneratorPaths,
                file: StaticString = #file,
                line: UInt = #line) throws
    {
        let targets = try manifest.targets.map { try TestableTarget.from(manifest: $0, generatorPaths: generatorPaths) }
        XCTAssertEqual(testAction.targets, targets, file: file, line: line)
        XCTAssertTrue(testAction.configurationName == manifest.configurationName, file: file, line: line)
        XCTAssertEqual(testAction.coverage, manifest.coverage, file: file, line: line)
        try optionalAssert(testAction.arguments, manifest.arguments) {
            assert(arguments: $0, matches: $1, file: file, line: line)
        }
    }

    func assert(runAction: TuistCore.RunAction,
                matches manifest: ProjectDescription.RunAction,
                path _: AbsolutePath,
                generatorPaths: GeneratorPaths,
                file: StaticString = #file,
                line: UInt = #line) throws
    {
        XCTAssertEqual(runAction.executable?.name, manifest.executable?.targetName)
        XCTAssertEqual(runAction.executable?.projectPath, try generatorPaths.resolveSchemeActionProjectPath(manifest.executable?.projectPath),
                       file: file,
                       line: line)
        XCTAssertTrue(runAction.configurationName == manifest.configurationName, file: file, line: line)
        try optionalAssert(runAction.arguments, manifest.arguments) {
            self.assert(arguments: $0, matches: $1, file: file, line: line)
        }
    }

    func assert(arguments: TuistCore.Arguments,
                matches manifest: ProjectDescription.Arguments,
                file: StaticString = #file,
                line: UInt = #line)
    {
        XCTAssertEqual(arguments.environment, manifest.environment, file: file, line: line)
        XCTAssertEqual(arguments.launch, manifest.launch, file: file, line: line)
    }

    fileprivate func optionalAssert<A, B>(_ optionalA: A?,
                                          _ optionalB: B?,
                                          file: StaticString = #file,
                                          line: UInt = #line,
                                          compare: (A, B) throws -> Void) throws
    {
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

private func == (_ lhs: TuistCore.Platform,
                 _ rhs: ProjectDescription.Platform) -> Bool
{
    let map: [TuistCore.Platform: ProjectDescription.Platform] = [
        .iOS: .iOS,
        .macOS: .macOS,
        .tvOS: .tvOS,
    ]
    return map[lhs] == rhs
}

private func == (_ lhs: TuistCore.Product,
                 _ rhs: ProjectDescription.Product) -> Bool
{
    let map: [TuistCore.Product: ProjectDescription.Product] = [
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

private func == (_ lhs: BuildConfiguration,
                 _ rhs: CustomConfiguration) -> Bool
{
    let map: [BuildConfiguration.Variant: CustomConfiguration.Variant] = [
        .debug: .debug,
        .release: .release,
    ]
    return map[lhs.variant] == rhs.variant && lhs.name == rhs.name
}
