import Path
import Testing
import XcodeGraph
@testable import TuistCore

struct GraphTraverserHostedPackageTests {
    @Test(arguments: [GraphDependency.PackageProductType.runtimeDynamic, .runtimeDynamicEmbedded])
    func hostedTestsRetainSharedDynamicProducts(type: GraphDependency.PackageProductType) throws {
        let fixture = graph(hostType: type, testType: type)
        let subject = GraphTraverser(graph: fixture)

        let dependencies = try subject.linkableDependencies(path: fixture.path, name: "AppTests")

        #expect(dependencies == [.packageProduct(product: "Shared")])
        #expect(try subject.linkableDependencies(path: fixture.path, name: "AppTests") == dependencies)
    }

    @Test(arguments: [GraphDependency.PackageProductType.runtime, .runtimeEmbedded])
    func existingSharedProductsRemainExcluded(type: GraphDependency.PackageProductType) throws {
        let fixture = graph(hostType: type, testType: type)
        let subject = GraphTraverser(graph: fixture)

        #expect(try subject.linkableDependencies(path: fixture.path, name: "AppTests").isEmpty)
    }

    @Test(arguments: [true, false])
    func dynamicHintOnEitherConsumerRetainsTheProduct(hintOnHost: Bool) throws {
        let fixture = graph(
            hostType: hintOnHost ? .runtimeDynamic : .runtime,
            testType: hintOnHost ? .runtime : .runtimeDynamic
        )
        let subject = GraphTraverser(graph: fixture)

        #expect(try subject.linkableDependencies(path: fixture.path, name: "AppTests") == [.packageProduct(product: "Shared")])
    }

    @Test
    func dynamicHintsOnlyAffectCoveredPlatforms() throws {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", destinations: [.iPhone, .mac], product: .app)
        let tests = Target.test(name: "AppTests", destinations: [.iPhone, .mac], product: .unitTests)
        let project = Project.test(path: path, targets: [app, tests])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        let shared = GraphDependency.packageProduct(path: path, product: "Shared", type: .runtime)
        let dynamic = GraphDependency.packageProduct(path: path, product: "Shared", type: .runtimeDynamic)
        let fixture = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [appDependency: [shared], testsDependency: [appDependency, shared, dynamic]],
            dependencyConditions: [GraphEdge(from: testsDependency, to: dynamic): try #require(.when([.ios]))]
        )
        let subject = GraphTraverser(graph: fixture)

        #expect(try subject.linkableDependencies(path: path, name: tests.name) == [
            .packageProduct(product: "Shared", condition: .when([.ios])),
        ])
    }

    @Test
    func mixedProductsRetainDynamicAndTestOnlyButNotHostStatics() throws {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: path, targets: [app, tests])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        let sharedStatic = GraphDependency.packageProduct(path: path, product: "Static", type: .runtime)
        let sharedDynamic = GraphDependency.packageProduct(path: path, product: "Dynamic", type: .runtimeDynamicEmbedded)
        let testOnly = GraphDependency.packageProduct(path: path, product: "TestOnly", type: .runtime)
        let fixture = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                appDependency: [sharedStatic, sharedDynamic],
                testsDependency: [appDependency, sharedStatic, sharedDynamic, testOnly],
            ]
        )
        let subject = GraphTraverser(graph: fixture)

        #expect(try subject.linkableDependencies(path: path, name: tests.name) == [
            .packageProduct(product: "Dynamic"), .packageProduct(product: "TestOnly"),
        ])
        #expect(subject.embeddableFrameworks(path: path, name: tests.name).isEmpty)
    }

    @Test(arguments: [false, true])
    func dynamicProductsPropagateThroughSourceAndCachedStaticChains(cached: Bool) throws {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let feature = Target.test(name: "Feature", product: .staticFramework)
        let project = Project.test(path: path, targets: [app, tests, feature])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        let featureDependency = cached
            ? GraphDependency.testXCFramework(path: "/Feature.xcframework", linking: .static)
            : .target(name: feature.name, path: path)
        let product = GraphDependency.packageProduct(path: path, product: "Dynamic", type: .runtimeDynamic)
        let fixture = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                appDependency: [featureDependency],
                testsDependency: [appDependency, featureDependency],
                featureDependency: [product],
            ]
        )
        let subject = GraphTraverser(graph: fixture)

        #expect(try subject.linkableDependencies(path: path, name: tests.name) == [.packageProduct(product: "Dynamic")])
        #expect(try subject.linkableDependencies(path: path, name: app.name).contains(.packageProduct(product: "Dynamic")))
        if !cached {
            #expect(try subject.linkableDependencies(path: path, name: feature.name).isEmpty)
            #expect(subject.packageProductsLinkedThroughStaticTargets(path: path, name: feature.name) == [
                .packageProduct(product: "Dynamic"),
            ])
        }
    }

    @Test(arguments: [false, true])
    func dynamicBoundariesDoNotPropagatePackageLinks(cached: Bool) throws {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let feature = Target.test(name: "Feature", product: .framework)
        let project = Project.test(path: path, targets: [app, tests, feature])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        let featureDependency = cached
            ? GraphDependency.testXCFramework(path: "/Feature.xcframework", linking: .dynamic)
            : .target(name: feature.name, path: path)
        let product = GraphDependency.packageProduct(path: path, product: "Dynamic", type: .runtimeDynamic)
        let fixture = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                appDependency: [featureDependency],
                testsDependency: [appDependency, featureDependency],
                featureDependency: [product],
            ]
        )
        let subject = GraphTraverser(graph: fixture)

        #expect(try !subject.linkableDependencies(path: path, name: tests.name).contains(.packageProduct(product: "Dynamic")))
        #expect(try !subject.linkableDependencies(path: path, name: app.name).contains(.packageProduct(product: "Dynamic")))
    }

    @Test
    func onlyDynamicEmbeddedProductsRemainEmbedded() throws {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: path, targets: [app, tests])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        let product = GraphDependency.packageProduct(path: path, product: "TestOnly", type: .runtimeDynamicEmbedded)
        let fixture = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [appDependency: [], testsDependency: [appDependency, product]]
        )
        let subject = GraphTraverser(graph: fixture)

        #expect(try subject.linkableDependencies(path: path, name: tests.name) == [.packageProduct(product: "TestOnly")])
        #expect(subject.embeddableFrameworks(path: path, name: tests.name) == [.packageProduct(product: "TestOnly")])
    }

    @Test
    func differentEmbedConditionsKeepExistingEmbeddingBehavior() throws {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", destinations: [.iPhone, .mac], product: .app)
        let tests = Target.test(name: "AppTests", destinations: [.iPhone, .mac], product: .unitTests)
        let project = Project.test(path: path, targets: [app, tests])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        let product = GraphDependency.packageProduct(path: path, product: "Shared", type: .runtimeDynamicEmbedded)
        let fixture = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [appDependency: [product], testsDependency: [appDependency, product]],
            dependencyConditions: [GraphEdge(from: testsDependency, to: product): try #require(.when([.macos]))]
        )
        let subject = GraphTraverser(graph: fixture)

        #expect(subject.embeddableFrameworks(path: path, name: tests.name) == [
            .packageProduct(product: "Shared", condition: .when([.macos])),
        ])
    }

    @Test
    func mixedDeclarationsWithoutAHostProductKeepTheirConditions() throws {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", destinations: [.iPhone, .mac], product: .app)
        let tests = Target.test(name: "AppTests", destinations: [.iPhone, .mac], product: .unitTests)
        let project = Project.test(path: path, targets: [app, tests])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        let dynamic = GraphDependency.packageProduct(path: path, product: "Shared", type: .runtimeDynamic)
        let legacy = GraphDependency.packageProduct(path: path, product: "Shared", type: .runtime)
        let fixture = Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [appDependency: [], testsDependency: [appDependency, dynamic, legacy]],
            dependencyConditions: [GraphEdge(from: testsDependency, to: dynamic): try #require(.when([.ios]))]
        )
        let subject = GraphTraverser(graph: fixture)

        #expect(try subject.linkableDependencies(path: path, name: tests.name) == [
            .packageProduct(product: "Shared"),
            .packageProduct(product: "Shared", condition: .when([.ios])),
        ])
    }

    private func graph(
        hostType: GraphDependency.PackageProductType,
        testType: GraphDependency.PackageProductType
    ) -> Graph {
        let path: AbsolutePath = "/project"
        let app = Target.test(name: "App", product: .app)
        let tests = Target.test(name: "AppTests", product: .unitTests)
        let project = Project.test(path: path, targets: [app, tests])
        let appDependency = GraphDependency.target(name: app.name, path: path)
        let testsDependency = GraphDependency.target(name: tests.name, path: path)
        return Graph.test(
            path: path,
            projects: [path: project],
            dependencies: [
                appDependency: [.packageProduct(path: path, product: "Shared", type: hostType)],
                testsDependency: [appDependency, .packageProduct(path: path, product: "Shared", type: testType)],
            ]
        )
    }
}
