import Foundation
import Path
import Testing
import TuistCore
import XcodeGraph
import XcodeProj
@testable import TuistGenerator

struct ForeignBuildCrossProjectDependencyGeneratorTests {
    private let subject = ForeignBuildCrossProjectDependencyGenerator()

    @Test func generate_wiresCrossProjectDependencyOnConsumer() async throws {
        let consumerPath = try AbsolutePath(validating: "/Workspace/Consumer")
        let aggregatePath = try AbsolutePath(validating: "/Workspace/Foreign")
        let outputPath = try AbsolutePath(validating: "/Workspace/Foreign/build/SharedKMP.xcframework")

        let aggregateTargetModel = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumerTargetModel = Target.test(
            name: "Framework1",
            dependencies: [.project(target: "SharedKMP", path: aggregatePath)]
        )
        let aggregateProjectModel = Project.test(path: aggregatePath, targets: [aggregateTargetModel])
        let consumerProjectModel = Project.test(path: consumerPath, targets: [consumerTargetModel])
        let graph = Graph.test(
            projects: [
                aggregatePath: aggregateProjectModel,
                consumerPath: consumerProjectModel,
            ],
            dependencies: [
                .target(name: "Framework1", path: consumerPath):
                    Set([.target(name: "SharedKMP", path: aggregatePath)]),
            ]
        )

        let aggregateDescriptor = makeDescriptor(
            path: aggregatePath,
            aggregateTargets: ["SharedKMP"]
        )
        let consumerDescriptor = makeDescriptor(
            path: consumerPath,
            nativeTargets: ["Framework1"]
        )

        try subject.generate(
            graphTraverser: GraphTraverser(graph: graph),
            projectDescriptors: [aggregateDescriptor, consumerDescriptor]
        )

        let consumerPbxproj = consumerDescriptor.xcodeProj.pbxproj
        let consumerTarget = try #require(
            consumerPbxproj.nativeTargets.first(where: { $0.name == "Framework1" })
        )
        let dependency = try #require(consumerTarget.dependencies.first)
        let proxy = try #require(dependency.targetProxy)

        #expect(dependency.name == "SharedKMP")
        #expect(dependency.target == nil)
        #expect(proxy.proxyType == .nativeTarget)
        #expect(proxy.remoteInfo == "SharedKMP")

        guard case let .fileReference(remoteRef) = proxy.containerPortal else {
            Issue.record("Expected .fileReference container portal, got \(proxy.containerPortal)")
            return
        }
        #expect(remoteRef.path == "../Foreign/Foreign.xcodeproj")
        #expect(remoteRef.lastKnownFileType == "wrapper.pb-project")

        let aggregateTarget = try #require(
            aggregateDescriptor.xcodeProj.pbxproj.aggregateTargets.first(where: { $0.name == "SharedKMP" })
        )
        // The remote global ID must point at the aggregate's stabilized UUID, otherwise Xcode
        // can't resolve the cross-project target dependency at build time.
        guard case let .object(remoteObject) = proxy.remoteGlobalID else {
            Issue.record("Expected remoteGlobalID to point at the aggregate target object")
            return
        }
        #expect(remoteObject.uuid == aggregateTarget.uuid)
        #expect(!aggregateTarget.uuid.hasPrefix("TEMP_"))

        let consumerPbxProject = try #require(consumerPbxproj.projects.first)
        let projectReferences = consumerPbxProject.projects
        #expect(projectReferences.count == 1)
        let projectReference = try #require(projectReferences.first)
        #expect(projectReference[Xcode.ProjectReference.projectReferenceKey] as? PBXFileReference == remoteRef)
        let productsGroup = try #require(
            projectReference[Xcode.ProjectReference.productGroupKey] as? PBXGroup
        )
        #expect(productsGroup.name == "Products")
        #expect(consumerPbxProject.mainGroup.children.contains(remoteRef))
    }

    @Test func generate_dedupesFileReferenceWhenMultipleConsumersShareAggregate() async throws {
        let consumerPath = try AbsolutePath(validating: "/Workspace/Consumer")
        let aggregatePath = try AbsolutePath(validating: "/Workspace/Foreign")
        let outputPath = try AbsolutePath(validating: "/Workspace/Foreign/build/SharedKMP.xcframework")

        let aggregateTargetModel = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumer1 = Target.test(
            name: "Framework1",
            dependencies: [.project(target: "SharedKMP", path: aggregatePath)]
        )
        let consumer2 = Target.test(
            name: "Framework2",
            dependencies: [.project(target: "SharedKMP", path: aggregatePath)]
        )
        let aggregateProjectModel = Project.test(path: aggregatePath, targets: [aggregateTargetModel])
        let consumerProjectModel = Project.test(path: consumerPath, targets: [consumer1, consumer2])
        let aggregateDep = GraphDependency.target(name: "SharedKMP", path: aggregatePath)
        let graph = Graph.test(
            projects: [
                aggregatePath: aggregateProjectModel,
                consumerPath: consumerProjectModel,
            ],
            dependencies: [
                .target(name: "Framework1", path: consumerPath): Set([aggregateDep]),
                .target(name: "Framework2", path: consumerPath): Set([aggregateDep]),
            ]
        )

        let aggregateDescriptor = makeDescriptor(
            path: aggregatePath,
            aggregateTargets: ["SharedKMP"]
        )
        let consumerDescriptor = makeDescriptor(
            path: consumerPath,
            nativeTargets: ["Framework1", "Framework2"]
        )

        try subject.generate(
            graphTraverser: GraphTraverser(graph: graph),
            projectDescriptors: [aggregateDescriptor, consumerDescriptor]
        )

        let consumerPbxproj = consumerDescriptor.xcodeProj.pbxproj
        let xcodeprojRefs = consumerPbxproj.fileReferences.filter { $0.lastKnownFileType == "wrapper.pb-project" }
        #expect(xcodeprojRefs.count == 1)

        let consumerPbxProject = try #require(consumerPbxproj.projects.first)
        #expect(consumerPbxProject.projects.count == 1)

        let framework1 = try #require(consumerPbxproj.nativeTargets.first(where: { $0.name == "Framework1" }))
        let framework2 = try #require(consumerPbxproj.nativeTargets.first(where: { $0.name == "Framework2" }))
        #expect(framework1.dependencies.count == 1)
        #expect(framework2.dependencies.count == 1)
    }

    @Test func generate_skipsSameProjectForeignBuild() async throws {
        let projectPath = try AbsolutePath(validating: "/Workspace/Project")
        let outputPath = try AbsolutePath(validating: "/Workspace/Project/build/SharedKMP.xcframework")

        let aggregateTargetModel = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumerTargetModel = Target.test(
            name: "Framework1",
            dependencies: [.target(name: "SharedKMP")]
        )
        let projectModel = Project.test(
            path: projectPath,
            targets: [aggregateTargetModel, consumerTargetModel]
        )
        let graph = Graph.test(
            projects: [projectPath: projectModel],
            dependencies: [
                .target(name: "Framework1", path: projectPath):
                    Set([.target(name: "SharedKMP", path: projectPath)]),
            ]
        )

        let descriptor = makeDescriptor(
            path: projectPath,
            nativeTargets: ["Framework1"],
            aggregateTargets: ["SharedKMP"]
        )

        try subject.generate(
            graphTraverser: GraphTraverser(graph: graph),
            projectDescriptors: [descriptor]
        )

        let consumer = try #require(descriptor.xcodeProj.pbxproj.nativeTargets.first(where: { $0.name == "Framework1" }))
        // Intra-project deps are handled by TargetGenerator; we must not also add a cross-project
        // proxy or we'd double-build the aggregate.
        #expect(consumer.dependencies.isEmpty)
        #expect(descriptor.xcodeProj.pbxproj.projects.first?.projects.isEmpty == true)
    }

    @Test func generate_appliesPlatformConditionFromTheGraphDependency() async throws {
        // Given a multi-platform consumer with an iOS-conditioned project dep on the foreign build.
        // Without forwarding the condition, the cross-project dep would unconditionally rope the
        // aggregate into every platform's build.
        let consumerPath = try AbsolutePath(validating: "/Workspace/Consumer")
        let aggregatePath = try AbsolutePath(validating: "/Workspace/Foreign")
        let outputPath = try AbsolutePath(validating: "/Workspace/Foreign/build/SharedKMP.xcframework")

        let aggregateTargetModel = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumerTargetModel = Target.test(
            name: "Framework1",
            destinations: [.iPhone, .mac],
            dependencies: [
                .project(target: "SharedKMP", path: aggregatePath, condition: .when([.ios])),
            ]
        )
        let aggregateProjectModel = Project.test(path: aggregatePath, targets: [aggregateTargetModel])
        let consumerProjectModel = Project.test(path: consumerPath, targets: [consumerTargetModel])
        let aggregateDep = GraphDependency.target(name: "SharedKMP", path: aggregatePath)
        let consumerDep = GraphDependency.target(name: "Framework1", path: consumerPath)
        let graph = Graph.test(
            projects: [
                aggregatePath: aggregateProjectModel,
                consumerPath: consumerProjectModel,
            ],
            dependencies: [consumerDep: Set([aggregateDep])],
            dependencyConditions: [GraphEdge(from: consumerDep, to: aggregateDep): .when([.ios])!]
        )

        let aggregateDescriptor = makeDescriptor(
            path: aggregatePath,
            aggregateTargets: ["SharedKMP"]
        )
        let consumerDescriptor = makeDescriptor(
            path: consumerPath,
            nativeTargets: ["Framework1"]
        )

        try subject.generate(
            graphTraverser: GraphTraverser(graph: graph),
            projectDescriptors: [aggregateDescriptor, consumerDescriptor]
        )

        let consumerPbxproj = consumerDescriptor.xcodeProj.pbxproj
        let framework1 = try #require(consumerPbxproj.nativeTargets.first(where: { $0.name == "Framework1" }))
        let dependency = try #require(framework1.dependencies.first)
        // applyCondition narrows to the intersection with the target's supported platforms — iOS,
        // which is strictly a subset of [iOS, macOS]. macOS must NOT see this dep.
        #expect(dependency.platformFilters == ["ios"] || dependency.platformFilter == "ios")
    }

    @Test func generate_ordersEdgesDeterministically() async throws {
        // Given two consumers depending on the same foreign build aggregate, the resulting pbxproj
        // mutations (PBXTargetDependency insertion order, PBXFileReference / PBXProject.projects
        // entries) must be stable across runs. Set-based iteration would scramble these.
        let consumerPath = try AbsolutePath(validating: "/Workspace/Consumer")
        let aggregate1Path = try AbsolutePath(validating: "/Workspace/Foreign1")
        let aggregate2Path = try AbsolutePath(validating: "/Workspace/Foreign2")
        let output1 = try AbsolutePath(validating: "/Workspace/Foreign1/build/A.xcframework")
        let output2 = try AbsolutePath(validating: "/Workspace/Foreign2/build/B.xcframework")

        let agg1 = Target.test(
            name: "AggregateA",
            foreignBuild: ForeignBuild(
                script: "build A",
                inputs: [],
                output: .xcframework(path: output1, linking: .dynamic)
            )
        )
        let agg2 = Target.test(
            name: "AggregateB",
            foreignBuild: ForeignBuild(
                script: "build B",
                inputs: [],
                output: .xcframework(path: output2, linking: .dynamic)
            )
        )
        let consumer1 = Target.test(
            name: "Framework1",
            dependencies: [
                .project(target: "AggregateA", path: aggregate1Path),
                .project(target: "AggregateB", path: aggregate2Path),
            ]
        )
        let consumer2 = Target.test(
            name: "Framework2",
            dependencies: [
                .project(target: "AggregateA", path: aggregate1Path),
                .project(target: "AggregateB", path: aggregate2Path),
            ]
        )
        let aggregate1 = Project.test(path: aggregate1Path, targets: [agg1])
        let aggregate2 = Project.test(path: aggregate2Path, targets: [agg2])
        let consumerProjectModel = Project.test(path: consumerPath, targets: [consumer1, consumer2])
        let depsA = Set([GraphDependency.target(name: "AggregateA", path: aggregate1Path)])
        let depsB = Set([GraphDependency.target(name: "AggregateB", path: aggregate2Path)])

        func runGeneration() throws -> [String] {
            let graph = Graph.test(
                projects: [
                    aggregate1Path: aggregate1,
                    aggregate2Path: aggregate2,
                    consumerPath: consumerProjectModel,
                ],
                dependencies: [
                    .target(name: "Framework1", path: consumerPath): depsA.union(depsB),
                    .target(name: "Framework2", path: consumerPath): depsA.union(depsB),
                ]
            )
            let aggregate1Descriptor = makeDescriptor(path: aggregate1Path, aggregateTargets: ["AggregateA"])
            let aggregate2Descriptor = makeDescriptor(path: aggregate2Path, aggregateTargets: ["AggregateB"])
            let consumerDescriptor = makeDescriptor(
                path: consumerPath,
                nativeTargets: ["Framework1", "Framework2"]
            )

            try subject.generate(
                graphTraverser: GraphTraverser(graph: graph),
                projectDescriptors: [aggregate1Descriptor, aggregate2Descriptor, consumerDescriptor]
            )

            let project = try #require(consumerDescriptor.xcodeProj.pbxproj.projects.first)
            let projectRefPaths = project.projects.compactMap {
                ($0[Xcode.ProjectReference.projectReferenceKey] as? PBXFileReference)?.path
            }
            let framework1Deps = try #require(
                consumerDescriptor.xcodeProj.pbxproj.nativeTargets
                    .first(where: { $0.name == "Framework1" })
            ).dependencies.compactMap(\.targetProxy?.remoteInfo)
            return projectRefPaths + framework1Deps
        }

        let firstRun = try runGeneration()
        let secondRun = try runGeneration()
        let thirdRun = try runGeneration()
        #expect(firstRun == secondRun)
        #expect(secondRun == thirdRun)
        // Sanity-check the actual order matches the lexicographic sort on (aggregatePath, name).
        #expect(firstRun.contains("../Foreign1/Foreign1.xcodeproj"))
        #expect(firstRun.contains("../Foreign2/Foreign2.xcodeproj"))
        #expect(firstRun.firstIndex(of: "AggregateA")! < firstRun.firstIndex(of: "AggregateB")!)
    }

    @Test func generate_isIdempotent() async throws {
        let consumerPath = try AbsolutePath(validating: "/Workspace/Consumer")
        let aggregatePath = try AbsolutePath(validating: "/Workspace/Foreign")
        let outputPath = try AbsolutePath(validating: "/Workspace/Foreign/build/SharedKMP.xcframework")

        let aggregateTargetModel = Target.test(
            name: "SharedKMP",
            foreignBuild: ForeignBuild(
                script: "gradle build",
                inputs: [],
                output: .xcframework(path: outputPath, linking: .dynamic)
            )
        )
        let consumerTargetModel = Target.test(
            name: "Framework1",
            dependencies: [.project(target: "SharedKMP", path: aggregatePath)]
        )
        let aggregateProjectModel = Project.test(path: aggregatePath, targets: [aggregateTargetModel])
        let consumerProjectModel = Project.test(path: consumerPath, targets: [consumerTargetModel])
        let graph = Graph.test(
            projects: [
                aggregatePath: aggregateProjectModel,
                consumerPath: consumerProjectModel,
            ],
            dependencies: [
                .target(name: "Framework1", path: consumerPath):
                    Set([.target(name: "SharedKMP", path: aggregatePath)]),
            ]
        )

        let aggregateDescriptor = makeDescriptor(
            path: aggregatePath,
            aggregateTargets: ["SharedKMP"]
        )
        let consumerDescriptor = makeDescriptor(
            path: consumerPath,
            nativeTargets: ["Framework1"]
        )

        try subject.generate(
            graphTraverser: GraphTraverser(graph: graph),
            projectDescriptors: [aggregateDescriptor, consumerDescriptor]
        )
        try subject.generate(
            graphTraverser: GraphTraverser(graph: graph),
            projectDescriptors: [aggregateDescriptor, consumerDescriptor]
        )

        let consumerPbxproj = consumerDescriptor.xcodeProj.pbxproj
        let framework1 = try #require(consumerPbxproj.nativeTargets.first(where: { $0.name == "Framework1" }))
        #expect(framework1.dependencies.count == 1)
        #expect(consumerPbxproj.projects.first?.projects.count == 1)
        #expect(consumerPbxproj.fileReferences.filter { $0.lastKnownFileType == "wrapper.pb-project" }.count == 1)
    }

    // MARK: - Helpers

    private func makeDescriptor(
        path: AbsolutePath,
        nativeTargets: [String] = [],
        aggregateTargets: [String] = []
    ) -> ProjectDescriptor {
        let mainGroup = PBXGroup()
        let configurationList = XCConfigurationList()
        let pbxProject = PBXProject(
            name: path.basename,
            buildConfigurationList: configurationList,
            compatibilityVersion: "1",
            preferredProjectObjectVersion: nil,
            minimizedProjectReferenceProxies: nil,
            mainGroup: mainGroup
        )
        let pbxproj = PBXProj(objectVersion: 70, archiveVersion: 10)
        pbxproj.add(object: mainGroup)
        pbxproj.add(object: configurationList)
        pbxproj.add(object: pbxProject)
        pbxproj.rootObject = pbxProject

        for name in nativeTargets {
            let productRef = PBXFileReference(
                sourceTree: .buildProductsDir,
                name: "\(name).framework",
                explicitFileType: "wrapper.framework",
                path: "\(name).framework",
                includeInIndex: false
            )
            pbxproj.add(object: productRef)
            let target = PBXNativeTarget(
                name: name,
                buildConfigurationList: nil,
                buildPhases: [],
                buildRules: [],
                dependencies: [],
                productInstallPath: nil,
                productName: name,
                product: productRef,
                productType: .framework
            )
            pbxproj.add(object: target)
            pbxProject.targets.append(target)
        }
        for name in aggregateTargets {
            let target = PBXAggregateTarget(
                name: name,
                buildConfigurationList: nil,
                buildPhases: [],
                buildRules: [],
                dependencies: [],
                productName: name
            )
            pbxproj.add(object: target)
            pbxProject.targets.append(target)
        }

        let xcodeProj = XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
        return ProjectDescriptor(
            path: path,
            xcodeprojPath: path.appending(component: "\(path.basename).xcodeproj"),
            xcodeProj: xcodeProj,
            schemeDescriptors: [],
            sideEffectDescriptors: []
        )
    }
}
