import Basic
import Foundation
import TuistCore
import xcodeproj
import XCTest

@testable import TuistCoreTesting
@testable import TuistKit

final class SchemeGeneratorTests: XCTestCase {
    var subject: SchemesGenerator!

    override func setUp() {
        super.setUp()
        subject = SchemesGenerator()
    }

    func test_testAction_when_notTestsTarget() {
        
        let scheme = Scheme.test()
        let project = Project.test()
        let generatedProject = GeneratedProject.test()
        
        let got = subject.testAction(scheme: scheme, project: project, generatedProject: generatedProject)
        
        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertNil(got?.macroExpansion)
        XCTAssertEqual(got?.testables.count, 0)
    }

    func test_testAction_when_testsTarget() {
        let target = Target.test(name: "App", product: .app)
        let testTarget = Target.test(name: "AppTests", product: .uiTests)
        let scheme = Scheme.test()
        let project = Project.test(targets: [target, testTarget])
        let pbxTarget = PBXNativeTarget(name: "App")
        let pbxTestTarget = PBXNativeTarget(name: "AppTests", productType: .unitTestBundle)
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget, "AppTests": pbxTestTarget])

        let got = subject.testAction(scheme: scheme, project: project, generatedProject: generatedProject)
        
        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertNil(got?.macroExpansion)
        let testable = got?.testables.first
        let buildableReference = testable?.buildableReference
        
        XCTAssertEqual(testable?.skipped, false)
        XCTAssertEqual(buildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference?.buildableName, testTarget.productName)
        XCTAssertEqual(buildableReference?.blueprintName, testTarget.name)
        XCTAssertEqual(buildableReference?.buildableIdentifier, "primary")
    }

    func test_buildAction() {
        let target = Target.test(name: "App", product: .app)
        let scheme = Scheme.test()
        let project = Project.test(targets: [target])
        let pbxTarget = PBXNativeTarget(name: "App")
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget])

        let got = subject.buildAction(scheme: scheme, project: project, generatedProject: generatedProject)

        XCTAssertEqual(got?.buildActionEntries.count, 1)
        let entry = got?.buildActionEntries.first
        let buildableReference = entry?.buildableReference
        XCTAssertEqual(entry?.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])

        XCTAssertEqual(buildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference?.buildableName, target.productName)
        XCTAssertEqual(buildableReference?.blueprintName, target.name)
        XCTAssertEqual(buildableReference?.buildableIdentifier, "primary")

        XCTAssertEqual(got?.parallelizeBuild, true)
        XCTAssertEqual(got?.buildImplicitDependencies, true)
    }

    func test_launchAction_when_runnableTarget() {
        let target = Target.test(name: "App", product: .app, environment: ["a": "b"])
        let scheme = Scheme.test()
        let project = Project.test(path: AbsolutePath("/project.xcodeproj"), targets: [target])
        let pbxTarget = PBXNativeTarget(name: "App")
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget])
        
        let got = subject.launchAction(scheme: scheme, project: project, generatedProject: generatedProject)

        XCTAssertNil(got?.macroExpansion)
        let buildableReference = got?.buildableProductRunnable?.buildableReference

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.environmentVariables, [XCScheme.EnvironmentVariable(variable: "a", value: "b", enabled: true)])
        XCTAssertEqual(buildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference?.buildableName, target.productName)
        XCTAssertEqual(buildableReference?.blueprintName, target.name)
        XCTAssertEqual(buildableReference?.buildableIdentifier, "primary")
    }

    func test_launchAction_when_notRunnableTarget() {
        let target = Target.test(name: "Library", product: .dynamicLibrary)
        let buildAction = BuildAction.test(targets: ["Library"])
        let testAction = TestAction.test(targets: ["Library"])

        let scheme = Scheme.test(name: "Library", buildAction: buildAction, testAction: testAction, runAction: nil)
        let project = Project.test(path: AbsolutePath("/project.xcodeproj"), targets: [target])
        let pbxTarget = PBXNativeTarget(name: "Library")
        let generatedProject = GeneratedProject.test(targets: ["Library": pbxTarget])

        let got = subject.launchAction(scheme: scheme, project: project, generatedProject: generatedProject)

        XCTAssertNil(got?.buildableProductRunnable?.buildableReference)

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.macroExpansion?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(got?.macroExpansion?.buildableName, target.productName)
        XCTAssertEqual(got?.macroExpansion?.blueprintName, target.name)
        XCTAssertEqual(got?.macroExpansion?.buildableIdentifier, "primary")
    }

    func test_profileAction_when_runnableTarget() {
        let target = Target.test(name: "App", platform: .iOS, product: .app)
        let scheme = Scheme.test()
        let pbxTarget = PBXNativeTarget(name: "App")
        let project = Project.test(path: AbsolutePath("/project.xcodeproj"), targets: [target])
        let generatedProject = GeneratedProject.test(targets: ["App": pbxTarget])

        let got = subject.profileAction(scheme: scheme, project: project, generatedProject: generatedProject)

        let buildable = got?.buildableProductRunnable?.buildableReference

        XCTAssertNil(got?.macroExpansion)
        XCTAssertEqual(got?.buildableProductRunnable?.runnableDebuggingMode, "0")
        XCTAssertEqual(buildable?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildable?.buildableName, target.productName)
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

    func test_profileAction_when_notRunnableTarget() {
        let target = Target.test(name: "Library", product: .dynamicLibrary)
        let buildAction = BuildAction.test(targets: ["Library"])
        let testAction = TestAction.test(targets: ["Library"])
        
        let scheme = Scheme.test(name: "Library", buildAction: buildAction, testAction: testAction, runAction: nil)
        let project = Project.test(path: AbsolutePath("/project.xcodeproj"), targets: [target])
        let pbxTarget = PBXNativeTarget(name: "Library")
        let generatedProject = GeneratedProject.test(targets: ["Library": pbxTarget])
        let got = subject.profileAction(scheme: scheme, project: project, generatedProject: generatedProject)

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
        XCTAssertEqual(got?.macroExpansion?.buildableName, target.productName)
        XCTAssertEqual(got?.macroExpansion?.blueprintName, target.name)
        XCTAssertEqual(got?.macroExpansion?.buildableIdentifier, "primary")
    }
    
    func test_analyzeAction() {
        let got = subject.analyzeAction()
        XCTAssertEqual(got.buildConfiguration, "Debug")
    }

    func test_archiveAction() {
        let scheme = Scheme.test()
        let project = Project.test()
        let generatedProject = GeneratedProject.test()

        let got = subject.archiveAction(scheme: scheme, project: project, generatedProject: generatedProject)
        XCTAssertEqual(got.buildConfiguration, "Release")
        XCTAssertEqual(got.revealArchiveInOrganizer, true)
    }
}
