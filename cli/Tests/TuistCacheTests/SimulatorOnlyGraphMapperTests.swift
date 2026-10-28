import Testing
import TuistCore
import XcodeGraph

@testable import TuistCache

struct SimulatorOnlyGraphMapperTests {
    @Test func restrictsConsumersWithoutChangingTheHashingGraphOrHostTools() throws {
        let app = Target.test(
            name: "App",
            destinations: [.iPhone, .iPad, .macCatalyst, .macWithiPadDesign],
            product: .app,
            settings: .test(
                base: [
                    "SUPPORTED_PLATFORMS": "iphoneos iphonesimulator",
                    "SUPPORTED_PLATFORMS[config=Debug]": "iphoneos",
                    "SDKROOT[sdk=iphonesimulator*]": "iphoneos",
                    "CUSTOM_SETTING": "preserved",
                ],
                baseDebug: ["SDKROOT": "iphoneos"],
                configurations: [
                    .release: .test(settings: ["SUPPORTED_PLATFORMS": "iphoneos", "SDKROOT": "iphoneos"]),
                ]
            )
        )
        let framework = Target.test(name: "Framework", destinations: [.iPhone], product: .framework)
        let tests = Target.test(name: "Tests", destinations: [.iPhone], product: .unitTests)
        let host = Target.test(name: "Host", destinations: [.mac], product: .framework)
        let macro = Target.test(name: "Macro", destinations: [.mac], product: .macro)
        let project = Project.test(targets: [app, framework, tests, host, macro])
        let graph = Graph.test(projects: [project.path: project], dependencies: [
            .target(name: "App", path: project.path): [.target(name: "Framework", path: project.path)],
            .target(name: "Tests", path: project.path): [.target(name: "App", path: project.path)],
        ])
        var environment = MapperEnvironment()
        environment.initialGraphWithSources = graph

        let (mapped, sideEffects, mappedEnvironment) = try SimulatorOnlyGraphMapper().map(graph: graph, environment: environment)
        let targets = try #require(mapped.projects[project.path]?.targets)
        for name in ["App", "Framework", "Tests"] {
            let target = try #require(targets[name])
            #expect(target.settings?.base["SUPPORTED_PLATFORMS"] == "iphonesimulator")
            #expect(target.settings?.base["SDKROOT"] == "iphonesimulator")
            #expect(!target.supportsCatalyst)
        }
        #expect(targets["App"]?.settings?.base["CUSTOM_SETTING"] == "preserved")
        #expect(targets["App"]?.settings?.base["SUPPORTED_PLATFORMS[config=Debug]"] == nil)
        #expect(targets["App"]?.settings?.base["SDKROOT[sdk=iphonesimulator*]"] == nil)
        #expect(targets["App"]?.settings?.baseDebug["SDKROOT"] == "iphonesimulator")
        let release = try #require(targets["App"]?.settings?.configurations[.release] ?? nil)
        #expect(release.settings["SUPPORTED_PLATFORMS"] == "iphonesimulator")
        #expect(release.settings["SDKROOT"] == "iphonesimulator")
        #expect(targets["Host"] == host)
        #expect(targets["Macro"] == macro)
        #expect(mapped.dependencies == graph.dependencies)
        #expect(mappedEnvironment.initialGraphWithSources == graph)
        #expect(sideEffects.isEmpty)
    }

    @Test func preservesNativeMacSupportForMultiplatformTargets() throws {
        let target = Target.test(name: "Shared", destinations: [.mac, .iPhone, .appleWatch, .appleTv, .appleVision])
        let catalystHost = Target.test(name: "CatalystHost", destinations: [.mac, .macCatalyst])
        let project = Project.test(targets: [target, catalystHost])
        let graph = Graph.test(projects: [project.path: project])

        let (mapped, _, _) = try SimulatorOnlyGraphMapper().map(graph: graph, environment: MapperEnvironment())
        let settings = try #require(mapped.projects[project.path]?.targets["Shared"]?.settings)
        if case let .string(platforms) = settings.base["SUPPORTED_PLATFORMS"] {
            #expect(Set(platforms.split(separator: " ")) == [
                "appletvsimulator", "iphonesimulator", "watchsimulator", "xrsimulator", "macosx",
            ])
        } else {
            Issue.record("Missing supported platforms")
        }
        #expect(settings.base["SDKROOT"] == "auto")
        #expect(mapped.projects[project.path]?.targets["CatalystHost"]?.settings?.base["SUPPORTED_PLATFORMS"] == "macosx")
    }

    @Test func rejectsCatalystOnlyTargetsInsteadOfGeneratingAnUnsupportedProject() throws {
        let project = Project.test(targets: [.test(name: "CatalystOnly", destinations: [.macCatalyst])])
        let graph = Graph.test(projects: [project.path: project])

        #expect(throws: SimulatorOnlyGraphMapperError.missingSimulatorDestination(target: "CatalystOnly")) {
            try SimulatorOnlyGraphMapper().map(graph: graph, environment: MapperEnvironment())
        }
    }
}
