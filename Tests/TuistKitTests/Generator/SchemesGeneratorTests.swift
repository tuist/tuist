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

    func test_buildAction_when_testsTarget() {
        let target = Target.test(name: "AppTests", product: .unitTests)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")

        let got = subject.buildAction(target: target,
                                      pbxTarget: pbxTarget,
                                      projectPath: projectPath)

        XCTAssertEqual(got?.buildActionEntries.count, 0)
        XCTAssertEqual(got?.parallelizeBuild, true)
        XCTAssertEqual(got?.buildImplicitDependencies, true)
    }

    func test_buildAction_when_notTestsTarget() {
        let target = Target.test(name: "App", product: .app)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")

        let got = subject.buildAction(target: target,
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

    func test_launchAction_when_runnableTarget() {
        let target = Target.test(name: "App", product: .app)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")
        let got = subject.launchAction(target: target,
                                       pbxTarget: pbxTarget,
                                       projectPath: projectPath)

        XCTAssertNil(got?.macroExpansion)
        let buildableReference = got?.buildableProductRunnable?.buildableReference

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(buildableReference?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(buildableReference?.buildableName, "App.app")
        XCTAssertEqual(buildableReference?.blueprintName, "App")
        XCTAssertEqual(buildableReference?.buildableIdentifier, "primary")
    }

    func test_launchAction_when_notRunnableTarget() {
        let target = Target.test(name: "Library",
                                 platform: .iOS,
                                 product: .dynamicLibrary)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")
        let got = subject.launchAction(target: target,
                                       pbxTarget: pbxTarget,
                                       projectPath: projectPath)

        XCTAssertNil(got?.buildableProductRunnable?.buildableReference)

        XCTAssertEqual(got?.buildConfiguration, "Debug")
        XCTAssertEqual(got?.macroExpansion?.referencedContainer, "container:project.xcodeproj")
        XCTAssertEqual(got?.macroExpansion?.buildableName, "libLibrary.dylib")
        XCTAssertEqual(got?.macroExpansion?.blueprintName, "Library")
        XCTAssertEqual(got?.macroExpansion?.buildableIdentifier, "primary")
    }

    func test_profileAction_when_runnableTarget() {
        let target = Target.test(name: "App",
                                 platform: .iOS,
                                 product: .app)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")
        let got = subject.profileAction(target: target,
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
        XCTAssertEqual(got?.enableTestabilityWhenProfilingTests, false)
    }

    func test_profileAction_when_notRunnableTarget() {
        let target = Target.test(name: "Library",
                                 platform: .iOS,
                                 product: .dynamicLibrary)
        let pbxTarget = PBXNativeTarget(name: "App")
        let projectPath = AbsolutePath("/project.xcodeproj")
        let got = subject.profileAction(target: target,
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

    func test_analyzeAction() {
        let got = subject.analyzeAction()
        XCTAssertEqual(got.buildConfiguration, "Debug")
    }

    func test_archiveAction() {
        let got = subject.archiveAction()
        XCTAssertEqual(got.buildConfiguration, "Release")
        XCTAssertEqual(got.revealArchiveInOrganizer, true)
    }
}
