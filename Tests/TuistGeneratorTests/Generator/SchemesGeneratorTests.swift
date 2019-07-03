import Basic
import Foundation
import TuistCore
import XcodeProj
import XCTest

@testable import TuistCoreTesting
@testable import TuistGenerator

final class SchemeGeneratorTests: XCTestCase {
    var subject: SchemesGenerator!

    override func setUp() {
        super.setUp()
        subject = SchemesGenerator()
    }

    func test_projectBuildAction() {
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let appUITests = Target.test(name: "AppUITests", product: .uiTests)
        let targets = [app, appTests, appUITests]

        let project = Project.test(targets: targets)
        let graphCache = GraphLoaderCache()
        let graph = Graph.test(cache: graphCache)

        let got = subject.projectBuildAction(project: project,
                                             generatedProject: generatedProject(targets: targets),
                                             graph: graph)

        XCTAssertTrue(got.parallelizeBuild)
        XCTAssertTrue(got.buildImplicitDependencies)
        XCTAssertEqual(got.buildActionEntries.count, 3)

        let appEntry = got.buildActionEntries[0]
        let testsEntry = got.buildActionEntries[1]
        let uiTestsEntry = got.buildActionEntries[2]

        XCTAssertEqual(appEntry.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])
        XCTAssertEqual(appEntry.buildableReference.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(appEntry.buildableReference.buildableName, app.productNameWithExtension)
        XCTAssertEqual(appEntry.buildableReference.blueprintName, app.name)
        XCTAssertEqual(appEntry.buildableReference.buildableIdentifier, "primary")

        XCTAssertEqual(testsEntry.buildFor, [.testing])
        XCTAssertEqual(testsEntry.buildableReference.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(testsEntry.buildableReference.buildableName, appTests.productNameWithExtension)
        XCTAssertEqual(testsEntry.buildableReference.blueprintName, appTests.name)
        XCTAssertEqual(testsEntry.buildableReference.buildableIdentifier, "primary")

        XCTAssertEqual(uiTestsEntry.buildFor, [.testing])
        XCTAssertEqual(uiTestsEntry.buildableReference.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(uiTestsEntry.buildableReference.buildableName, appUITests.productNameWithExtension)
        XCTAssertEqual(uiTestsEntry.buildableReference.blueprintName, appUITests.name)
        XCTAssertEqual(uiTestsEntry.buildableReference.buildableIdentifier, "primary")
    }

    func test_projectTestAction() {
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let targets = [app, appTests]
        let project = Project.test(targets: targets)

        let got = subject.projectTestAction(project: project,
                                            generatedProject: generatedProject(targets: targets))

        XCTAssertEqual(got.buildConfiguration, "Debug")
        XCTAssertNil(got.macroExpansion)
        XCTAssertEqual(got.testables.count, 1)

        let testable = got.testables.first
        XCTAssertEqual(testable?.skipped, false)

        XCTAssertEqual(testable?.buildableReference.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(testable?.buildableReference.buildableName, appTests.productNameWithExtension)
        XCTAssertEqual(testable?.buildableReference.blueprintName, appTests.name)
        XCTAssertEqual(testable?.buildableReference.buildableIdentifier, "primary")
    }

    func test_schemeTestAction_when_notTestsTarget() {
        let scheme = Scheme.test()
        let project = Project.test()
        let generatedProject = GeneratedProject.test()

        let got = subject.schemeTestAction(scheme: scheme, project: project, generatedProject: generatedProject)

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.shouldUseLaunchSchemeArgsEnv, false)
        XCTAssertNil(got?.macroExpansion)
        XCTAssertEqual(got?.testables.count, 0)
    }

    func test_schemeTestAction_when_testsTarget() {
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .unitTests)

        let testAction = TestAction.test(arguments: nil)
        let scheme = Scheme.test(name: "AppTests", testAction: testAction)
        let project = Project.test(targets: [target, testTarget])

        let pbxTarget = PBXNativeTarget(name: "App")
        let pbxTestTarget = PBXNativeTarget(name: "AppTests", productType: .unitTestBundle)
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget, "AppTests": pbxTestTarget])

        let got = subject.schemeTestAction(scheme: scheme, project: project, generatedProject: generatedProject)

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertNil(got?.macroExpansion)
        let testable = got?.testables.first
        let buildableReference = testable?.buildableReference

        XCTAssertEqual(testable?.skipped, false)
        XCTAssertEqual(buildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference?.buildableName, "AppTests.xctest")
        XCTAssertEqual(buildableReference?.blueprintName, "AppTests")
        XCTAssertEqual(buildableReference?.buildableIdentifier, "primary")
    }

    func test_schemeTestAction_with_executionAction() {
        let testTarget = Target.test(name: "AppTests", product: .unitTests)

        let preAction = ExecutionAction(title: "Pre Action", scriptText: "echo Pre Actions", target: "AppTests")
        let postAction = ExecutionAction(title: "Post Action", scriptText: "echo Post Actions", target: "AppTests")
        let testAction = TestAction.test(targets: ["AppTests"], preActions: [preAction], postActions: [postAction])

        let scheme = Scheme.test(name: "AppTests", shared: true, testAction: testAction)
        let project = Project.test(targets: [testTarget])

        let pbxTestTarget = PBXNativeTarget(name: "AppTests", productType: .unitTestBundle)
        let generatedProject = GeneratedProject.test(targets: ["AppTests": pbxTestTarget])

        let got = subject.schemeTestAction(scheme: scheme, project: project, generatedProject: generatedProject)

        // Pre Action
        XCTAssertEqual(got?.preActions.first?.title, "Pre Action")
        XCTAssertEqual(got?.preActions.first?.scriptText, "echo Pre Actions")

        let preBuildableReference = got?.preActions.first?.environmentBuildable

        XCTAssertEqual(preBuildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(preBuildableReference?.buildableName, "AppTests.xctest")
        XCTAssertEqual(preBuildableReference?.blueprintName, "AppTests")
        XCTAssertEqual(preBuildableReference?.buildableIdentifier, "primary")

        // Post Action
        XCTAssertEqual(got?.postActions.first?.title, "Post Action")
        XCTAssertEqual(got?.postActions.first?.scriptText, "echo Post Actions")

        let postBuildableReference = got?.postActions.first?.environmentBuildable

        XCTAssertEqual(postBuildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(postBuildableReference?.buildableName, "AppTests.xctest")
        XCTAssertEqual(postBuildableReference?.blueprintName, "AppTests")
        XCTAssertEqual(postBuildableReference?.buildableIdentifier, "primary")
    }

    func test_schemeBuildAction() {
        let target = Target.test(name: "App", product: .app)
        let pbxTarget = PBXNativeTarget(name: "App")

        let scheme = Scheme.test(name: "App")
        let project = Project.test(targets: [target])
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget])

        let got = subject.schemeBuildAction(scheme: scheme, project: project, generatedProject: generatedProject)

        XCTAssertEqual(got?.buildActionEntries.count, 1)
        let entry = got?.buildActionEntries.first
        let buildableReference = entry?.buildableReference
        XCTAssertEqual(entry?.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])

        XCTAssertEqual(buildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference?.buildableName, "App.app")
        XCTAssertEqual(buildableReference?.blueprintName, "App")
        XCTAssertEqual(buildableReference?.buildableIdentifier, "primary")

        XCTAssertEqual(got?.parallelizeBuild, true)
        XCTAssertEqual(got?.buildImplicitDependencies, true)
    }

    func test_schemeBuildAction_with_executionAction() {
        let target = Target.test(name: "App", product: .app)
        let pbxTarget = PBXNativeTarget(name: "App")

        let preAction = ExecutionAction(title: "Pre Action", scriptText: "echo Pre Actions", target: "App")
        let postAction = ExecutionAction(title: "Post Action", scriptText: "echo Post Actions", target: "App")
        let buildAction = BuildAction.test(targets: ["Library"], preActions: [preAction], postActions: [postAction])

        let scheme = Scheme.test(name: "App", shared: true, buildAction: buildAction)
        let project = Project.test(targets: [target])
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget])

        let got = subject.schemeBuildAction(scheme: scheme, project: project, generatedProject: generatedProject)

        // Pre Action
        XCTAssertEqual(got?.preActions.first?.title, "Pre Action")
        XCTAssertEqual(got?.preActions.first?.scriptText, "echo Pre Actions")

        let preBuildableReference = got?.preActions.first?.environmentBuildable

        XCTAssertEqual(preBuildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(preBuildableReference?.buildableName, "App.app")
        XCTAssertEqual(preBuildableReference?.blueprintName, "App")
        XCTAssertEqual(preBuildableReference?.buildableIdentifier, "primary")

        // Post Action
        XCTAssertEqual(got?.postActions.first?.title, "Post Action")
        XCTAssertEqual(got?.postActions.first?.scriptText, "echo Post Actions")

        let postBuildableReference = got?.postActions.first?.environmentBuildable

        XCTAssertEqual(postBuildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(postBuildableReference?.buildableName, "App.app")
        XCTAssertEqual(postBuildableReference?.blueprintName, "App")
        XCTAssertEqual(postBuildableReference?.buildableIdentifier, "primary")
    }

    func test_schemeLaunchAction_when_runnableTarget() {
        let target = Target.test(name: "App", product: .app, environment: ["a": "b"])
        let pbxTarget = PBXNativeTarget(name: "App")
        let scheme = Scheme.test(runAction: RunAction.test(arguments: Arguments.test(environment: ["a": "b"])))
        let project = Project.test(path: AbsolutePath("/project.xcodeproj"), targets: [target])
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget])

        let got = subject.schemeLaunchAction(scheme: scheme, project: project, generatedProject: generatedProject)

        XCTAssertNil(got?.macroExpansion)
        let buildableReference = got?.runnable?.buildableReference

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.environmentVariables, [XCScheme.EnvironmentVariable(variable: "a", value: "b", enabled: true)])
        XCTAssertEqual(buildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference?.buildableName, "App.app")
        XCTAssertEqual(buildableReference?.blueprintName, "App")
        XCTAssertEqual(buildableReference?.buildableIdentifier, "primary")
    }

    func test_schemeLaunchAction_when_notRunnableTarget() {
        let target = Target.test(name: "Library", platform: [.iOS], product: .dynamicLibrary)
        let pbxTarget = PBXNativeTarget(name: "App")

        let buildAction = BuildAction.test(targets: ["Library"])
        let testAction = TestAction.test(targets: ["Library"])

        let scheme = Scheme.test(name: "Library", buildAction: buildAction, testAction: testAction, runAction: nil)

        let project = Project.test(path: AbsolutePath("/project.xcodeproj"), targets: [target])
        let generatedProject = GeneratedProject.test(targets: ["Library": pbxTarget])

        let got = subject.schemeLaunchAction(scheme: scheme, project: project, generatedProject: generatedProject)

        XCTAssertNil(got?.runnable?.buildableReference)

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.macroExpansion?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(got?.macroExpansion?.buildableName, "libLibrary.dylib")
        XCTAssertEqual(got?.macroExpansion?.blueprintName, "Library")
        XCTAssertEqual(got?.macroExpansion?.buildableIdentifier, "primary")
    }

    func test_schemeProfileAction_when_runnableTarget() {
        let target = Target.test(name: "App", platform: [.iOS], product: .app)
        let scheme = Scheme.test()
        let pbxTarget = PBXNativeTarget(name: "App")
        let project = Project.test(path: AbsolutePath("/project.xcodeproj"), targets: [target])
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget])

        let got = subject.schemeProfileAction(scheme: scheme, project: project, generatedProject: generatedProject)

        let buildable = got?.buildableProductRunnable?.buildableReference

        XCTAssertNil(got?.macroExpansion)
        XCTAssertEqual(got?.buildableProductRunnable?.runnableDebuggingMode, "0")
        XCTAssertEqual(buildable?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildable?.buildableName, target.productNameWithExtension)
        XCTAssertEqual(buildable?.blueprintName, target.name)
        XCTAssertEqual(buildable?.buildableIdentifier, "primary")

        XCTAssertEqual(got?.buildConfiguration, "Release")
        XCTAssertEqual(got?.preActions, [])
        XCTAssertEqual(got?.postActions, [])
        XCTAssertEqual(got?.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertEqual(got?.savedToolIdentifier, "")
        XCTAssertEqual(got?.ignoresPersistentStateOnLaunch, false)
        XCTAssertEqual(got?.useCustomWorkingDirectory, false)
        XCTAssertEqual(got?.debugDocumentVersioning, true)
        XCTAssertNil(got?.commandlineArguments)
        XCTAssertNil(got?.environmentVariables)
        XCTAssertEqual(got?.enableTestabilityWhenProfilingTests, true)
    }

    func test_schemeProfileAction_when_notRunnableTarget() {
        let target = Target.test(name: "Library", platform: [.iOS], product: .dynamicLibrary)

        let buildAction = BuildAction.test(targets: ["Library"])
        let testAction = TestAction.test(targets: ["Library"])
        let scheme = Scheme.test(name: "Library", buildAction: buildAction, testAction: testAction, runAction: nil)

        let project = Project.test(path: AbsolutePath("/project.xcodeproj"), targets: [target])
        let pbxTarget = PBXNativeTarget(name: "Library")
        let generatedProject = GeneratedProject.test(targets: ["Library": pbxTarget])

        let got = subject.schemeProfileAction(scheme: scheme, project: project, generatedProject: generatedProject)

        let buildable = got?.buildableProductRunnable?.buildableReference

        XCTAssertNil(buildable)
        XCTAssertEqual(got?.buildConfiguration, "Release")
        XCTAssertEqual(got?.preActions, [])
        XCTAssertEqual(got?.postActions, [])
        XCTAssertEqual(got?.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertEqual(got?.savedToolIdentifier, "")
        XCTAssertEqual(got?.ignoresPersistentStateOnLaunch, false)
        XCTAssertEqual(got?.useCustomWorkingDirectory, false)
        XCTAssertEqual(got?.debugDocumentVersioning, true)
        XCTAssertNil(got?.commandlineArguments)
        XCTAssertNil(got?.environmentVariables)
        XCTAssertEqual(got?.enableTestabilityWhenProfilingTests, true)

        XCTAssertEqual(got?.buildConfiguration, "Release")
        XCTAssertEqual(got?.macroExpansion?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(got?.macroExpansion?.buildableName, "libLibrary.dylib")
        XCTAssertEqual(got?.macroExpansion?.blueprintName, "Library")
        XCTAssertEqual(got?.macroExpansion?.buildableIdentifier, "primary")
    }

    func test_schemeAnalyzeAction() {
        let got = subject.schemeAnalyzeAction()
        XCTAssertEqual(got.buildConfiguration, "Debug")
    }

    func test_schemeArchiveAction() {
        let got = subject.schemeArchiveAction()
        XCTAssertEqual(got.buildConfiguration, "Release")
        XCTAssertEqual(got.revealArchiveInOrganizer, true)
    }

    // MARK: - Private

    private func generatedProject(targets: [Target]) -> GeneratedProject {
        var pbxTargets: [String: PBXNativeTarget] = [:]
        targets.forEach { pbxTargets[$0.name] = PBXNativeTarget(name: $0.name) }
        return GeneratedProject(pbxproj: .init(), path: AbsolutePath("/project.xcodeproj"), targets: pbxTargets, name: "project.xcodeproj")
    }
}
