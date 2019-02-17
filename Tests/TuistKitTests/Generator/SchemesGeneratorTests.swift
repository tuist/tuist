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
    
    func test_projectBuildAction() {
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let pbxAppTarget = PBXNativeTarget(name: "App")
        let pbxAppTestsTarget = PBXNativeTarget(name: "AppTests")
        let projectPath = AbsolutePath("/project.xcodeproj")
        
        let targets = ["App": pbxAppTarget,
                       "AppTests": pbxAppTestsTarget]
        let project = Project.test(targets: [app, appTests])
        
        let generatedProject = GeneratedProject(path: projectPath,
                                                targets: targets)
        let got = subject.projectBuildAction(project: project,
                                            generatedProject: generatedProject)
        
        XCTAssertTrue(got.parallelizeBuild)
        XCTAssertTrue(got.buildImplicitDependencies)
        XCTAssertEqual(got.buildActionEntries.count, 2)
        
        let appEntry = got.buildActionEntries.first
        let testsEntry = got.buildActionEntries.last
        
        XCTAssertEqual(appEntry?.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])
        XCTAssertEqual(appEntry?.buildFor, [.analyzing, .archiving, .profiling, .running, .testing])
        XCTAssertEqual(appEntry?.buildableReference.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(appEntry?.buildableReference.buildableName, app.productName)
        XCTAssertEqual(appEntry?.buildableReference.blueprintName, app.name)
        XCTAssertEqual(appEntry?.buildableReference.buildableIdentifier, "primary")

        XCTAssertEqual(testsEntry?.buildFor, [.testing])
        XCTAssertEqual(testsEntry?.buildableReference.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(testsEntry?.buildableReference.buildableName, appTests.productName)
        XCTAssertEqual(testsEntry?.buildableReference.blueprintName, appTests.name)
        XCTAssertEqual(testsEntry?.buildableReference.buildableIdentifier, "primary")
    }
    
    func test_projectTestAction() {
        let app = Target.test(name: "App", product: .app)
        let appTests = Target.test(name: "AppTests", product: .unitTests)
        let pbxAppTarget = PBXNativeTarget(name: "App")
        let pbxAppTestsTarget = PBXNativeTarget(name: "AppTests")
        let projectPath = AbsolutePath("/project.xcodeproj")

        let targets = ["App": pbxAppTarget,
                       "AppTests": pbxAppTestsTarget]
        let project = Project.test(targets: [app, appTests])
        
        let generatedProject = GeneratedProject(path: projectPath,
                                                targets: targets)
        let got = subject.projectTestAction(project: project,
                                            generatedProject: generatedProject)
        
        XCTAssertEqual(got.buildConfiguration, "Debug")
        XCTAssertNil(got.macroExpansion)
        XCTAssertEqual(got.testables.count, 1)
        
        let testable = got.testables.first
        XCTAssertEqual(testable?.skipped, false)
        
        XCTAssertEqual(testable?.buildableReference.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(testable?.buildableReference.buildableName, appTests.productName)
        XCTAssertEqual(testable?.buildableReference.blueprintName, appTests.name)
        XCTAssertEqual(testable?.buildableReference.buildableIdentifier, "primary")
    }

    func test_targetTestAction_when_notTestsTarget() {
        let target = Target.test(name: "AppTests", product: .app)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")

        let got = subject.targetTestAction(target: target,
                                     pbxTarget: pbxTarget,
                                     projectPath: projectPath)

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.shouldUseLaunchSchemeArgsEnv, true)
        XCTAssertNil(got?.macroExpansion)
        XCTAssertEqual(got?.testables.count, 0)
    }

    func test_targetTestAction_when_testsTarget() {
        let target = Target.test(name: "AppTests", product: .unitTests)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")

        let got = subject.targetTestAction(target: target,
                                     pbxTarget: pbxTarget,
                                     projectPath: projectPath)

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

    func test_targetBuildAction() {
        let target = Target.test(name: "App", product: .app)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")

        let got = subject.targetBuildAction(target: target,
                                      pbxTarget: pbxTarget,
                                      projectPath: projectPath)

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

    func test_targetLaunchAction_when_runnableTarget() {
        let target = Target.test(name: "App", product: .app, environment: ["a": "b"])
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")
        let got = subject.targetLaunchAction(target: target,
                                       pbxTarget: pbxTarget,
                                       projectPath: projectPath)

        XCTAssertNil(got?.macroExpansion)
        let buildableReference = got?.buildableProductRunnable?.buildableReference

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.environmentVariables, [XCScheme.EnvironmentVariable(variable: "a", value: "b", enabled: true)])
        XCTAssertEqual(buildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference?.buildableName, "App.app")
        XCTAssertEqual(buildableReference?.blueprintName, "App")
        XCTAssertEqual(buildableReference?.buildableIdentifier, "primary")
    }

    func test_targetLaunchAction_when_notRunnableTarget() {
        let target = Target.test(name: "Library",
                                 platform: .iOS,
                                 product: .dynamicLibrary)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")
        let got = subject.targetLaunchAction(target: target,
                                       pbxTarget: pbxTarget,
                                       projectPath: projectPath)

        XCTAssertNil(got?.buildableProductRunnable?.buildableReference)

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.macroExpansion?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(got?.macroExpansion?.buildableName, "libLibrary.dylib")
        XCTAssertEqual(got?.macroExpansion?.blueprintName, "Library")
        XCTAssertEqual(got?.macroExpansion?.buildableIdentifier, "primary")
    }

    func test_targetProfileAction_when_runnableTarget() {
        let target = Target.test(name: "App",
                                 platform: .iOS,
                                 product: .app)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")
        let got = subject.targetProfileAction(target: target,
                                        pbxTarget: pbxTarget,
                                        projectPath: projectPath)

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

    func test_targetProfileAction_when_notRunnableTarget() {
        let target = Target.test(name: "Library",
                                 platform: .iOS,
                                 product: .dynamicLibrary)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")
        let got = subject.targetProfileAction(target: target,
                                        pbxTarget: pbxTarget,
                                        projectPath: projectPath)

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

    func test_targetAnalyzeAction() {
        let got = subject.targetAnalyzeAction()
        XCTAssertEqual(got.buildConfiguration, "Debug")
    }

    func test_targetArchiveAction() {
        let got = subject.targetArchiveAction()
        XCTAssertEqual(got.buildConfiguration, "Release")
        XCTAssertEqual(got.revealArchiveInOrganizer, true)
    }
}
