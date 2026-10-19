import Foundation
import Path
import Testing
import TuistCore
import TuistTesting
import XcodeGraph

@testable import TuistKit

struct InstrumentedBinaryCacheWarmGraphMapperTests {
    @Test func map_marksTheRepositoryBinariesOnly() async throws {
        let localPath = try AbsolutePath(validating: "/local")
        let externalPath = try AbsolutePath(validating: "/external")
        let framework = Target.test(
            name: "Core",
            product: .framework,
            settings: Settings(
                base: ["SWIFT_VERSION": "5"],
                baseDebug: ["ENABLE_TESTABILITY": "YES"],
                configurations: [.debug: Configuration(settings: ["OTHER_SWIFT_FLAGS": "-DDEBUG"])],
                defaultSettings: .essential(excluding: ["CODE_SIGN_IDENTITY"]),
                defaultConfiguration: "Debug"
            )
        )
        let library = Target.test(name: "Utils", product: .staticLibrary, settings: nil)
        let bundle = Target.test(name: "Assets", product: .bundle)
        let macro = Target.test(name: "Macros", product: .macro)
        let tests = Target.test(name: "CoreTests", product: .unitTests)
        let local = Project.test(
            path: localPath,
            settings: .test(defaultSettings: .none),
            targets: [framework, library, bundle, macro, tests],
            type: .local
        )
        let external = Project.test(
            path: externalPath,
            targets: [Target.test(name: "Dependency", product: .framework)],
            type: .external(hash: nil)
        )
        let graph = Graph.test(projects: [localPath: local, externalPath: external])

        let (got, sideEffects, _) = try await InstrumentedBinaryCacheWarmGraphMapper().map(
            graph: graph,
            environment: MapperEnvironment()
        )

        #expect(sideEffects.isEmpty)
        let marker = InstrumentedBinaryCacheWarm.markerSetting
        let targets = got.projects[localPath]!.targets
        #expect(targets["Core"]?.settings == Settings(
            base: ["SWIFT_VERSION": "5", marker: "YES"],
            baseDebug: ["ENABLE_TESTABILITY": "YES"],
            configurations: [.debug: Configuration(settings: ["OTHER_SWIFT_FLAGS": "-DDEBUG"])],
            defaultSettings: .essential(excluding: ["CODE_SIGN_IDENTITY"]),
            defaultConfiguration: "Debug"
        ))
        // A target without settings keeps resolving its defaults from the project, as the generator does.
        #expect(targets["Utils"]?.settings == Settings(base: [marker: "YES"], configurations: [:], defaultSettings: .none))
        #expect(targets["Assets"]?.settings?.base[marker] == nil)
        #expect(targets["Macros"]?.settings?.base[marker] == nil)
        #expect(targets["CoreTests"]?.settings?.base[marker] == nil)
        #expect(got.projects[externalPath]?.targets["Dependency"]?.settings?.base[marker] == nil)
        #expect(got.projects[localPath]?.settings.base[marker] == nil)
    }
}
