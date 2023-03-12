import Foundation
import TSCBasic
import TuistCore
import TuistCoreTesting
import TuistGraph
import TuistGraphTesting
import TuistSupport
import XCTest
@testable import TuistGenerator
@testable import TuistSupportTesting

final class TargetLinterTests: TuistUnitTestCase {
    var subject: TargetLinter!

    override func setUp() {
        super.setUp()
        subject = TargetLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_when_target_has_invalid_product_name() {
        let XCTAssertInvalidProductNameApp: (Target) -> Void = { target in
            let got = self.subject.lint(target: target)
            let reason = target.product == .app ?
                "Invalid product name '\(target.productName)'. This string must contain only alphanumeric (A-Z,a-z,0-9), period (.), and underscore (_) characters." :
                "Invalid product name '\(target.productName)'. This string must contain only alphanumeric (A-Z,a-z,0-9), and underscore (_) characters."
            self.XCTContainsLintingIssue(got, LintingIssue(reason: reason, severity: .warning))
        }

        let XCTAssertValidProductNameApp: (Target) -> Void = { target in
            let got = self.subject.lint(target: target)
            XCTAssertNil(got.first(where: { $0.description.contains("Invalid product name") }))
        }

        XCTAssertValidProductNameApp(Target.test(product: .app, productName: "MyApp.iOS"))
        XCTAssertValidProductNameApp(Target.test(productName: "MyFramework_iOS"))
        XCTAssertValidProductNameApp(Target.test(productName: "MyFramework"))

        XCTAssertInvalidProductNameApp(Target.test(product: .framework, productName: "MyFramework.iOS"))
        XCTAssertInvalidProductNameApp(Target.test(productName: "MyFramework-iOS"))
        XCTAssertInvalidProductNameApp(Target.test(productName: "ⅫFramework"))
        XCTAssertInvalidProductNameApp(Target.test(productName: "ؼFramework"))
    }

    func test_lint_when_target_has_invalid_bundle_identifier() {
        let XCTAssertInvalidBundleId: (String) -> Void = { bundleId in
            let target = Target.test(bundleId: bundleId)
            let got = self.subject.lint(target: target)
            let reason =
                "Invalid bundle identifier '\(bundleId)'. This string must be a uniform type identifier (UTI) that contains only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.) characters."
            self.XCTContainsLintingIssue(got, LintingIssue(reason: reason, severity: .error))
        }
        let XCTAssertValidBundleId: (String) -> Void = { bundleId in
            let target = Target.test(bundleId: bundleId)
            let got = self.subject.lint(target: target)
            XCTAssertNil(got.first(where: { $0.description.contains("Invalid bundle identifier") }))
        }

        XCTAssertInvalidBundleId("_.company.app")
        XCTAssertInvalidBundleId("com.company.◌́")
        XCTAssertInvalidBundleId("Ⅻ.company.app")
        XCTAssertInvalidBundleId("ؼ.company.app")
        XCTAssertValidBundleId("com.company.MyModule${BUNDLE_SUFFIX}")
    }

    func test_lint_when_target_no_source_files() {
        let target = Target.test(sources: [])
        let got = subject.lint(target: target)

        XCTContainsLintingIssue(
            got,
            LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)
        )
    }

    func test_lint_when_target_no_source_files_but_has_dependency() {
        let target = Target.test(sources: [], dependencies: [
            TargetDependency.sdk(name: "libc++.tbd", status: .optional),
        ])
        let got = subject.lint(target: target)

        XCTAssertEqual(0, got.count)
    }

    func test_lint_when_target_no_source_files_but_has_actions() {
        let target = Target.test(sources: [], scripts: [
            TargetScript(name: "Test script", order: .post, script: .embedded("echo 'This is a test'")),
        ])
        let got = subject.lint(target: target)

        XCTAssertEqual(0, got.count)
    }

    func test_lint_when_a_infoplist_file_is_being_copied() {
        let infoPlistPath = try! AbsolutePath(validating: "/Info.plist")
        let googeServiceInfoPlistPath = try! AbsolutePath(validating: "/GoogleService-Info.plist")

        let target = Target.test(
            infoPlist: .file(path: infoPlistPath),
            resources: [
                .file(path: infoPlistPath),
                .file(path: googeServiceInfoPlistPath),
            ]
        )

        let got = subject.lint(target: target)

        XCTContainsLintingIssue(
            got,
            LintingIssue(
                reason: "Info.plist at path \(infoPlistPath.pathString) being copied into the target \(target.name) product.",
                severity: .warning
            )
        )
        XCTDoesNotContainLintingIssue(
            got,
            LintingIssue(
                reason: "Info.plist at path \(googeServiceInfoPlistPath.pathString) being copied into the target \(target.name) product.",
                severity: .warning
            )
        )
    }

    func test_lint_when_a_entitlements_file_is_being_copied() {
        let path = try! AbsolutePath(validating: "/App.entitlements")
        let target = Target.test(resources: [.file(path: path)])

        let got = subject.lint(target: target)

        XCTContainsLintingIssue(
            got,
            LintingIssue(
                reason: "Entitlements file at path \(path.pathString) being copied into the target \(target.name) product.",
                severity: .warning
            )
        )
    }

    func test_lint_when_entitlements_not_missing() throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "Info.plist")
        let target = Target.test(infoPlist: .file(path: path))

        let got = subject.lint(target: target)

        XCTContainsLintingIssue(
            got,
            LintingIssue(reason: "Info.plist file not found at path \(path.pathString)", severity: .error)
        )
    }

    func test_lint_when_infoplist_not_found() throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "App.entitlements")
        let target = Target.test(entitlements: path)

        let got = subject.lint(target: target)

        XCTContainsLintingIssue(
            got,
            LintingIssue(reason: "Entitlements file not found at path \(path.pathString)", severity: .error)
        )
    }

    func test_lint_when_library_has_resources() throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "Image.png")
        let element = ResourceFileElement.file(path: path)

        let staticLibrary = Target.test(product: .staticLibrary, resources: [element])
        let dynamicLibrary = Target.test(product: .dynamicLibrary, resources: [element])

        let staticResult = subject.lint(target: staticLibrary)
        XCTContainsLintingIssue(
            staticResult,
            LintingIssue(
                reason: "Target \(staticLibrary.name) cannot contain resources. static library targets do not support resources",
                severity: .error
            )
        )

        let dynamicResult = subject.lint(target: dynamicLibrary)
        XCTContainsLintingIssue(
            dynamicResult,
            LintingIssue(
                reason: "Target \(dynamicLibrary.name) cannot contain resources. dynamic library targets do not support resources",
                severity: .error
            )
        )
    }

    func test_lint_when_ios_bundle_has_sources() {
        // Given
        let bundle = Target.empty(
            platform: .iOS,
            product: .bundle,
            sources: [
                SourceFile(path: "/path/to/some/source.swift"),
            ],
            resources: []
        )

        // When
        let result = subject.lint(target: bundle)

        // Then
        XCTContainsLintingIssue(
            result,
            LintingIssue(
                reason: "Target \(bundle.name) cannot contain sources. iOS bundle targets don't support source files",
                severity: .error
            )
        )
    }

    func test_lint_valid_ios_bundle() {
        // Given
        let bundle = Target.empty(
            platform: .iOS,
            product: .bundle,
            resources: [
                .file(path: "/path/to/some/asset.png"),
            ]
        )

        // When
        let result = subject.lint(target: bundle)

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_when_deployment_target_version_is_valid() {
        let validVersions = ["10.0", "9.0.1"]
        for version in validVersions {
            // Given
            let target = Target.test(platform: .macOS, deploymentTarget: .macOS(version))

            // When
            let got = subject.lint(target: target)

            // Then
            XCTDoesNotContainLintingIssue(
                got,
                LintingIssue(reason: "The version of deployment target is incorrect", severity: .error)
            )
        }
    }

    func test_lint_when_deployment_target_version_is_invalid() {
        let validVersions = ["tuist", "tuist9.0.1", "1.0tuist", "10_0", "1_1_3"]
        for version in validVersions {
            // Given
            let target = Target.test(platform: .macOS, deploymentTarget: .macOS(version))

            // When
            let got = subject.lint(target: target)

            // Then
            XCTContainsLintingIssue(got, LintingIssue(reason: "The version of deployment target is incorrect", severity: .error))
        }
    }

    func test_lint_when_target_platform_and_deployment_target_property_mismatch() throws {
        let invalidCombinations: [(Platform, DeploymentTarget)] = [
            (.iOS, .macOS("10.0.0")),
            (.watchOS, .macOS("10.0.0")),
            (.macOS, .watchOS("10.0.0")),
            (.tvOS, .macOS("10.0.0")),
        ]
        for combinations in invalidCombinations {
            // Given
            let target = Target.test(platform: combinations.0, deploymentTarget: combinations.1)

            // When
            let got = subject.lint(target: target)

            // Then
            XCTContainsLintingIssue(
                got,
                LintingIssue(
                    reason: "Found an inconsistency between a platform `\(combinations.0.caseValue)` and deployment target `\(combinations.1.platform)`",
                    severity: .error
                )
            )
        }
    }

    func test_lint_invalidProductPlatformCombinations() throws {
        // Given
        let invalidTargets: [Target] = [
            .empty(name: "WatchApp_for_iOS", platform: .iOS, product: .watch2App),
            .empty(name: "Watch2Extension_for_iOS", platform: .iOS, product: .watch2Extension),
        ]

        // When
        let got = invalidTargets.flatMap { subject.lint(target: $0) }

        // Then
        let expectedIssues: [LintingIssue] = [
            LintingIssue(
                reason: "'WatchApp_for_iOS' for platform 'iOS' can't have a product type 'watch 2 application'",
                severity: .error
            ),
            LintingIssue(
                reason: "'Watch2Extension_for_iOS' for platform 'iOS' can't have a product type 'watch 2 extension'",
                severity: .error
            ),
        ]
        XCTAssertTrue(expectedIssues.allSatisfy { got.contains($0) })
    }

    func test_lint_when_target_has_duplicate_dependencies_specified() {
        let testDependency: TargetDependency = .sdk(name: "libc++.tbd", status: .optional)

        // Given
        let target = Target.test(dependencies: .init(repeating: testDependency, count: 2))

        // When
        let got = subject.lint(target: target)

        // Then
        XCTContainsLintingIssue(got, .init(
            reason: "Target '\(target.name)' has duplicate sdk dependency specified: 'libc++.tbd'",
            severity: .warning
        ))
    }

    func test_lint_when_target_has_non_existing_core_data_models() throws {
        // Given
        let path = try temporaryPath()
        let dataModelPath = path.appending(component: "Model.xcdatamodeld")
        let target = Target.test(coreDataModels: [
            CoreDataModel(path: dataModelPath, versions: [], currentVersion: "1.0.0"),
        ])

        // When
        let got = subject.lint(target: target)

        // Then
        XCTContainsLintingIssue(got, .init(
            reason: "The Core Data model at path \(dataModelPath.pathString) does not exist",
            severity: .error
        ))
    }

    func test_lint_when_target_has_core_data_models_with_default_versions_that_dont_exist() throws {
        // Given
        let path = try temporaryPath()
        let dataModelPath = path.appending(component: "Model.xcdatamodeld")
        try FileHandler.shared.createFolder(dataModelPath)

        let target = Target.test(coreDataModels: [
            CoreDataModel(path: dataModelPath, versions: [], currentVersion: "1.0.0"),
        ])

        // When
        let got = subject.lint(target: target)

        // Then
        XCTContainsLintingIssue(got, .init(
            reason: "The default version of the Core Data model at path \(dataModelPath.pathString), 1.0.0, does not exist. There should be a file at \(dataModelPath.appending(component: "1.0.0.xcdatamodel").pathString)",
            severity: .error
        ))
    }

    func test_lint_when_target_has_valid_codegen_sources() throws {
        // Given
        let target = Target.empty(
            name: "MyTarget",
            sources: [
                SourceFile(path: "/project/Source.swift"),
                SourceFile(path: "/project/Invalid.swift", codeGen: .project),
                SourceFile(path: "/project/Unspecified.intentdefinition"),
                SourceFile(path: "/project/Valid.intentdefinition", codeGen: .private),
                SourceFile(path: "/project/Valid.mlmodel", codeGen: .disabled),
            ]
        )

        // When
        let got = subject.lint(target: target)

        // Then
        XCTContainsLintingIssue(got, .init(
            reason: "Target '\(target.name)' has a source file at path \(target.sources[1].path) with unsupported `codeGen` attributes. Only intentdefinition and mlmodel are known to support this.",
            severity: .warning
        ))
    }
}
