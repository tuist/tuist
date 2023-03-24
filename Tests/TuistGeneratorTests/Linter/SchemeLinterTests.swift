import Foundation
import TSCBasic
import TuistCore
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

class SchemeLinterTests: TuistTestCase {
    var subject: SchemeLinter!

    override func setUp() {
        super.setUp()
        subject = SchemeLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_missingConfigurations() {
        // Given
        let settings = Settings(configurations: [
            .release("Beta"): .test(),
        ])
        let scheme = Scheme(
            name: "CustomScheme",
            testAction: .test(configurationName: "Alpha"),
            runAction: .test(configurationName: "CustomDebug")
        )
        let project = Project.test(settings: settings, schemes: [scheme])

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got.first?.severity, .error)
        XCTAssertEqual(got.last?.severity, .error)
        XCTAssertEqual(
            got.first?.reason,
            "The build configuration 'CustomDebug' specified in the scheme's run action isn't defined in the project."
        )
        XCTAssertEqual(
            got.last?.reason,
            "The build configuration 'Alpha' specified in the scheme's test action isn't defined in the project."
        )
    }

    func test_lint_referenceLocalTarget() {
        // Given
        let project = Project.test(schemes: [
            .init(
                name: "SchemeWithTargetThatDoesExist",
                shared: true,
                buildAction: .init(targets: [.init(projectPath: try! AbsolutePath(validating: "/Project"), name: "Target")])
            ),
        ])

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertTrue(got.isEmpty)
    }

    func test_lint_referenceRemoteTargetBuildAction() {
        // Given
        let project = Project.test(schemes: [
            .init(
                name: "SchemeWithTargetThatDoesNotExist",
                shared: true,
                buildAction: .init(targets: [.init(
                    projectPath: try! AbsolutePath(validating: "/Project/../Framework"),
                    name: "Framework"
                )])
            ),
        ])

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got.first?.severity, .error)
        XCTAssertEqual(
            got.first?.reason,
            "The target 'Framework' specified in scheme 'SchemeWithTargetThatDoesNotExist' is not defined in the project named 'Project'. Consider using a workspace scheme instead to reference a target in another project."
        )
    }

    func test_lint_referenceRemoteTargetTestAction() {
        // Given
        let settings = Settings(configurations: [
            .release("Beta"): .test(),
        ])

        let project = Project.test(
            settings: settings,
            schemes: [
                .init(
                    name: "SchemeWithTargetThatDoesNotExist",
                    shared: true,
                    testAction: .init(
                        targets: [.init(target: .init(
                            projectPath: try! AbsolutePath(validating: "/Project/../Framework"),
                            name: "Framework"
                        ))],
                        arguments: nil,
                        configurationName: "Beta",
                        attachDebugger: true,
                        coverage: false,
                        codeCoverageTargets: [],
                        expandVariableFromTarget: nil,
                        preActions: [],
                        postActions: [],
                        diagnosticsOptions: []
                    )
                ),
            ]
        )

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got.first?.severity, .error)
        XCTAssertEqual(
            got.first?.reason,
            "The target 'Framework' specified in scheme 'SchemeWithTargetThatDoesNotExist' is not defined in the project named 'Project'. Consider using a workspace scheme instead to reference a target in another project."
        )
    }

    func test_lint_referenceRemoteTargetExecutionAction() {
        // Given
        let project = Project.test(schemes: [
            .init(
                name: "SchemeWithTargetThatDoesNotExist",
                shared: true,
                buildAction: .init(preActions: [.init(
                    title: "Something",
                    scriptText: "Script",
                    target: .init(
                        projectPath: try! AbsolutePath(validating: "/Project/../Project2"),
                        name: "Target2"
                    )
                )])
            ),
        ])

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got.first?.severity, .error)
        XCTAssertEqual(
            got.first?.reason,
            "The target 'Target2' specified in scheme 'SchemeWithTargetThatDoesNotExist' is not defined in the project named 'Project'. Consider using a workspace scheme instead to reference a target in another project."
        )
    }

    func test_lint_missingStoreKitConfiguration() {
        // Given
        let project = Project.test(
            settings: Settings(configurations: [
                BuildConfiguration.debug: Configuration(settings: .init(), xcconfig: nil),
            ]),
            schemes: [
                .init(
                    name: "Scheme",
                    shared: true,
                    runAction: .test(
                        options: .init(storeKitConfigurationPath: "/non/existing/path/configuration.storekit")
                    )
                ),
            ]
        )

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got.first?.severity, .error)
        XCTAssertEqual(
            got.first?.reason,
            "StoreKit configuration file not found at path /non/existing/path/configuration.storekit"
        )
    }

    func test_lint_existingStoreKitConfiguration() {
        // Given
        let project = Project.test(
            settings: Settings(configurations: [
                BuildConfiguration.debug: Configuration(settings: .init(), xcconfig: nil),
            ]),
            schemes: [
                .init(
                    name: "Scheme",
                    shared: true,
                    runAction: .test(
                        options: .init(storeKitConfigurationPath: "/non/existing/path/configuration.storekit")
                    )
                ),
            ]
        )

        fileHandler.stubExists = { path in
            path.pathString == "/non/existing/path/configuration.storekit"
        }

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEmpty(got)
    }
}
