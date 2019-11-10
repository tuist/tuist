import Basic
import Foundation
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
        let XCTAssertInvalidProductName: (String) -> Void = { productName in
            let target = Target.test(productName: productName)
            let got = self.subject.lint(target: target)
            let reason = "Invalid product name '\(productName)'. This string must contain only alphanumeric (A-Z,a-z,0-9) and underscore (_) characters."
            XCTAssertTrue(got.contains(LintingIssue(reason: reason, severity: .error)))
        }

        let XCTAssertValidProductName: (String) -> Void = { bundleId in
            let target = Target.test(bundleId: bundleId)
            let got = self.subject.lint(target: target)
            XCTAssertNil(got.first(where: { $0.description.contains("Invalid product name") }))
        }

        XCTAssertInvalidProductName("MyFramework-iOS")
        XCTAssertInvalidProductName("My.Framework")
        XCTAssertInvalidProductName("ⅫFramework")
        XCTAssertInvalidProductName("ؼFramework")
        XCTAssertValidProductName("MyFramework_iOS")
        XCTAssertValidProductName("MyFramework")
    }

    func test_lint_when_target_has_invalid_bundle_identifier() {
        let XCTAssertInvalidBundleId: (String) -> Void = { bundleId in
            let target = Target.test(bundleId: bundleId)
            let got = self.subject.lint(target: target)
            let reason = "Invalid bundle identifier '\(bundleId)'. This string must be a uniform type identifier (UTI) that contains only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.) characters."
            XCTAssertTrue(got.contains(LintingIssue(reason: reason, severity: .error)))
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
        XCTAssertTrue(got.contains(LintingIssue(reason: "The target \(target.name) doesn't contain source files.", severity: .warning)))
    }

    func test_lint_when_a_infoplist_file_is_being_copied() {
        let path = AbsolutePath("/Info.plist")
        let target = Target.test(resources: [.file(path: path)])

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Info.plist at path \(path.pathString) being copied into the target \(target.name) product.", severity: .warning)))
    }

    func test_lint_when_a_entitlements_file_is_being_copied() {
        let path = AbsolutePath("/App.entitlements")
        let target = Target.test(resources: [.file(path: path)])

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Entitlements file at path \(path.pathString) being copied into the target \(target.name) product.", severity: .warning)))
    }

    func test_lint_when_entitlements_not_missing() throws {
        let temporaryPath = try self.temporaryPath()
        let path = temporaryPath.appending(component: "Info.plist")
        let target = Target.test(infoPlist: .file(path: path))

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Info.plist file not found at path \(path.pathString)", severity: .error)))
    }

    func test_lint_when_infoplist_not_found() throws {
        let temporaryPath = try self.temporaryPath()
        let path = temporaryPath.appending(component: "App.entitlements")
        let target = Target.test(entitlements: path)

        let got = subject.lint(target: target)

        XCTAssertTrue(got.contains(LintingIssue(reason: "Entitlements file not found at path \(path.pathString)", severity: .error)))
    }

    func test_lint_when_library_has_resources() throws {
        let temporaryPath = try self.temporaryPath()
        let path = temporaryPath.appending(component: "Image.png")
        let element = FileElement.file(path: path)

        let staticLibrary = Target.test(product: .staticLibrary, resources: [element])
        let dynamicLibrary = Target.test(product: .dynamicLibrary, resources: [element])

        let staticResult = subject.lint(target: staticLibrary)
        XCTAssertTrue(staticResult.contains(LintingIssue(reason: "Target \(staticLibrary.name) cannot contain resources. Libraries don't support resources", severity: .error)), staticResult.description)

        let dynamicResult = subject.lint(target: dynamicLibrary)
        XCTAssertTrue(dynamicResult.contains(LintingIssue(reason: "Target \(dynamicLibrary.name) cannot contain resources. Libraries don't support resources", severity: .error)), dynamicResult.description)
    }

    func test_lint_when_ios_bundle_has_sources() {
        // Given
        let bundle = Target.empty(platform: .iOS,
                                  product: .bundle,
                                  sources: [
                                      (path: "/path/to/some/source.swift", compilerFlags: nil),
                                  ],
                                  resources: [])

        // When
        let result = subject.lint(target: bundle)

        // Then
        let sortedResults = result.sorted(by: { $0.reason < $1.reason })
        XCTAssertEqual(sortedResults, [
            LintingIssue(reason: "Target \(bundle.name) cannot contain sources. iOS bundle targets don't support source files", severity: .error),
        ])
    }

    func test_lint_valid_ios_bundle() {
        // Given
        let bundle = Target.empty(platform: .iOS,
                                  product: .bundle,
                                  resources: [
                                      .file(path: "/path/to/some/asset.png"),
                                  ])

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
            XCTAssertFalse(got.contains(LintingIssue(reason: "The version of deployment target is incorrect", severity: .error)))
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
            XCTAssertTrue(got.contains(LintingIssue(reason: "The version of deployment target is incorrect", severity: .error)))
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
            LintingIssue(reason: "'WatchApp_for_iOS' for platform 'iOS' can't have a product type 'watch 2 application'", severity: .error),
            LintingIssue(reason: "'Watch2Extension_for_iOS' for platform 'iOS' can't have a product type 'watch 2 extension'",
                         severity: .error),
        ]
        XCTAssertTrue(expectedIssues.allSatisfy { got.contains($0) })
    }

	func test_lint_when_target_has_duplicate_dependencies_specified() {
		let testDependency: Dependency = .sdk(name: "libc++.tbd", status: .optional)

		// Given
		let target = Target.test(dependencies: .init(repeating: testDependency, count: 2))

		// When
		let got = subject.lint(target: target)

		// Then
		XCTAssertTrue(
			got.contains(
				.init(
					reason: "Target has duplicate '\(testDependency)' dependency specified",
					severity: .warning
				)
			)
		)
    }
}
