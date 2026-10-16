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
        let framework = Target.test(name: "Core", product: .framework, settings: .test(base: ["SWIFT_VERSION": "5"]))
        let library = Target.test(name: "Utils", product: .staticLibrary, settings: nil)
        let bundle = Target.test(name: "Assets", product: .bundle)
        let macro = Target.test(name: "Macros", product: .macro)
        let tests = Target.test(name: "CoreTests", product: .unitTests)
        let local = Project.test(path: localPath, targets: [framework, library, bundle, macro, tests], type: .local)
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
        #expect(targets["Core"]?.settings?.base == ["SWIFT_VERSION": "5", marker: "YES"])
        #expect(targets["Utils"]?.settings?.base[marker] == "YES")
        #expect(targets["Assets"]?.settings?.base[marker] == nil)
        #expect(targets["Macros"]?.settings?.base[marker] == nil)
        #expect(targets["CoreTests"]?.settings?.base[marker] == nil)
        #expect(got.projects[externalPath]?.targets["Dependency"]?.settings?.base[marker] == nil)
        #expect(got.projects[localPath]?.settings.base[marker] == nil)
    }
}
