import Foundation
import Path
import TuistCore
import TuistSupport
import XcodeGraph
import XCTest
@testable import TuistGenerator
@testable import TuistTesting

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

    func test_lint_when_target_has_invalid_product_name() async throws {
        let XCTAssertInvalidProductNameApp: (Target) async throws -> Void = { target in
            let got = try await self.subject.lint(target: target, options: .test())
            let reason: String
            switch target.product {
            case .framework, .staticFramework:
                reason =
                    "Invalid product name '\(target.productName)'. This string must contain only alphanumeric (A-Z,a-z,0-9), and underscore (_) characters."
            default:
                reason =
                    "Invalid product name '\(target.productName)'. This string must contain only alphanumeric (A-Z,a-z,0-9), period (.), hyphen (-), and underscore (_) characters."
            }

            XCTAssertTrue(got.contains(LintingIssue(reason: reason, severity: .warning)))
        }

        let XCTAssertValidProductNameApp: (Target) async throws -> Void = { target in
            let got = try await self.subject.lint(target: target, options: .test())
            XCTAssertNil(got.first(where: { $0.description.contains("Invalid product name") }))
        }

        try await XCTAssertValidProductNameApp(Target.test(product: .app, productName: "MyApp.iOS"))
        try await XCTAssertValidProductNameApp(Target.test(product: .app, productName: "MyApp-iOS"))
        try await XCTAssertValidProductNameApp(Target.test(product: .bundle, productName: "MyBundle.macOS"))
        try await XCTAssertValidProductNameApp(Target.test(product: .bundle, productName: "MyBundle-macOS"))
        try await XCTAssertValidProductNameApp(Target.test(productName: "MyFramework_iOS"))
        try await XCTAssertValidProductNameApp(Target.test(productName: "MyFramework"))

        try await XCTAssertInvalidProductNameApp(Target.test(product: .framework, productName: "MyFramework.iOS"))
        try await XCTAssertInvalidProductNameApp(Target.test(product: .framework, productName: "MyFramework-iOS"))
        try await XCTAssertInvalidProductNameApp(Target.test(productName: "ⅫFramework"))
        try await XCTAssertInvalidProductNameApp(Target.test(productName: "ؼFramework"))
    }

    func test_lint_when_inconsistentProductNameBuildSettingAcrossConfigurations() async throws {
        // Given
        let target = Target.test(settings: .test(
            base: ["PRODUCT_NAME": "1"],
            debug: .test(settings: ["PRODUCT_NAME": "2"]),
            release: .test(settings: ["PRODUCT_NAME": "3"])
        ))

        // When
        let got = try await subject.lint(target: target, options: .test())

        // Then
        XCTAssertTrue(got.contains(LintingIssue(
            reason: "The target '\(target.name)' has a PRODUCT_NAME build setting that is different across configurations and might cause unpredictable behaviours.",
            severity: .warning
        )))
    }

    func test_lint_when_productNameBuildSettingWithVariables() async throws {
        // Given
        let target = Target.test(settings: .test(
            base: ["PRODUCT_NAME": "$VARIABLE"],
            debug: .test(settings: ["PRODUCT_NAME": "$VARIABLE"]),
            release: .test(settings: ["PRODUCT_NAME": "$VARIABLE"])
        ))

        // When
        let got = try await subject.lint(target: target, options: .test())

        // Then
        XCTAssertTrue(got.contains(LintingIssue(
            reason: "The target '\(target.name)' has a PRODUCT_NAME build setting containing variables that are resolved at build time, and might cause unpredictable behaviours.",
            severity: .warning
        )))
    }

    func test_lint_when_target_has_invalid_bundle_identifier() async throws {
        let XCTAssertInvalidBundleId: (String) async throws -> Void = { bundleId in
            let target = Target.test(bundleId: bundleId)
            let got = try await self.subject.lint(target: target, options: .test())
            let reason =
                "Invalid bundle identifier '\(bundleId)'. This string must be a uniform type identifier (UTI) that contains only alphanumeric (A-Z,a-z,0-9), hyphen (-), and period (.) characters."
            XCTAssertTrue(got.contains(LintingIssue(reason: reason, severity: .error)))
        }
        let XCTAssertValidBundleId: (String) async throws -> Void = { bundleId in
            let target = Target.test(bundleId: bundleId)
            let got = try await self.subject.lint(target: target, options: .test())
            XCTAssertNil(got.first(where: { $0.description.contains("Invalid bundle identifier") }))
        }

        try await XCTAssertInvalidBundleId("_.company.app")
        try await XCTAssertInvalidBundleId("com.company.◌́")
        try await XCTAssertInvalidBundleId("Ⅻ.company.app")
        try await XCTAssertInvalidBundleId("ؼ.company.app")
        try await XCTAssertValidBundleId("com.company.MyModule${BUNDLE_SUFFIX}")
    }

    func test_lint_when_target_no_source_files_but_remote() async throws {
        let target = Target(
            name: "Target",
            destinations: .iOS,
            product: .framework,
            productName: nil,
            bundleId: "bundle.id",
            filesGroup: .group(name: "Project"),
            type: .remote
        )
        let got = try await subject.lint(target: target, options: .test())

        XCTAssertEmpty(got)
    }

    func test_lint_when_target_no_source_files_but_has_dependency() async throws {
        let target = Target.test(sources: [], dependencies: [
            TargetDependency.sdk(name: "libc++.tbd", status: .optional),
        ])
        let got = try await subject.lint(target: target, options: .test())

        XCTAssertEqual(0, got.count)
    }

    func test_lint_when_target_no_source_files_but_has_actions() async throws {
        let target = Target.test(sources: [], scripts: [
            TargetScript(name: "Test script", order: .post, script: .embedded("echo 'This is a test'")),
        ])
        let got = try await subject.lint(target: target, options: .test())

        XCTAssertEqual(0, got.count)
    }

    func test_lint_when_a_infoplist_file_is_being_copied() async throws {
        let infoPlistPath = try! AbsolutePath(validating: "/Info.plist")
        let googeServiceInfoPlistPath = try! AbsolutePath(validating: "/GoogleService-Info.plist")

        let target = Target.test(
            infoPlist: .file(path: infoPlistPath),
            resources: .init(
                [
                    .file(path: infoPlistPath),
                    .file(path: googeServiceInfoPlistPath),
                ]
            )
        )

        let got = try await subject.lint(target: target, options: .test())

        XCTAssertTrue(got.contains(LintingIssue(
            reason: "Info.plist at path \(infoPlistPath.pathString) being copied into the target \(target.name) product.",
            severity: .warning
        )))
        XCTAssertFalse(got.contains(LintingIssue(
            reason: "Info.plist at path \(googeServiceInfoPlistPath.pathString) being copied into the target \(target.name) product.",
            severity: .warning
        )))
    }

    func test_lint_when_a_entitlements_file_is_being_copied() async throws {
        let path = try! AbsolutePath(validating: "/App.entitlements")
        let target = Target.test(resources: .init([.file(path: path)]))

        let got = try await subject.lint(target: target, options: .test())

        XCTAssertTrue(got.contains(LintingIssue(
            reason: "Entitlements file at path \(path.pathString) being copied into the target \(target.name) product.",
            severity: .warning
        )))
    }

    func test_lint_when_entitlements_not_missing() async throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "Info.plist")
        let target = Target.test(infoPlist: .file(path: path))

        let got = try await subject.lint(target: target, options: .test())

        XCTAssertTrue(got.contains(LintingIssue(
            reason: "Info.plist file not found at path \(path.pathString)",
            severity: .error
        )))
    }

    func test_lint_when_infoplist_not_found() async throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "App.entitlements")
        let target = Target.test(entitlements: .file(path: path))

        let got = try await subject.lint(target: target, options: .test())

        XCTAssertTrue(got.contains(LintingIssue(
            reason: "Entitlements file not found at path \(path.pathString)",
            severity: .error
        )))
    }

    func test_lint_when_library_has_resources() async throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "Image.png")
        let element = ResourceFileElement.file(path: path)

        let staticLibrary = Target.test(product: .staticLibrary, resources: .init([element]))
        let dynamicLibrary = Target.test(product: .dynamicLibrary, resources: .init([element]))

        let staticLibraryResult = try await subject.lint(
            target: staticLibrary,
            options: .test()
        )
        XCTAssertFalse(staticLibraryResult.contains(LintingIssue(
            reason: "Target \(staticLibrary.name) cannot contain resources. For \(staticLibrary.product) targets to support resources, 'Bundle Accessors' feature should be enabled.",
            severity: .error
        )))

        let dynamicLibraryResult = try await subject.lint(
            target: dynamicLibrary,
            options: .test()
        )
        XCTAssertFalse(dynamicLibraryResult.contains(LintingIssue(
            reason: "Target \(dynamicLibrary.name) cannot contain resources. For \(dynamicLibrary.product) targets to support resources, 'Bundle Accessors' feature should be enabled.",
            severity: .error
        )))
    }

    func test_lint_when_library_has_resources_with_disable_bundle_accessors() async throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "Image.png")
        let element = ResourceFileElement.file(path: path)

        let staticLibrary = Target.test(product: .staticLibrary, resources: .init([element]))
        let dynamicLibrary = Target.test(product: .dynamicLibrary, resources: .init([element]))

        let staticLibraryResult = try await subject.lint(
            target: staticLibrary,
            options: .test(disableBundleAccessors: true)
        )
        XCTAssertTrue(staticLibraryResult.contains(LintingIssue(
            reason: "Target \(staticLibrary.name) cannot contain resources. For \(staticLibrary.product) targets to support resources, 'Bundle Accessors' feature should be enabled.",
            severity: .error
        )))

        let dynamicLibraryResult = try await subject.lint(
            target: dynamicLibrary,
            options: .test(disableBundleAccessors: true)
        )
        XCTAssertTrue(
            dynamicLibraryResult.contains(LintingIssue(
                reason: "Target \(dynamicLibrary.name) cannot contain resources. For \(dynamicLibrary.product) targets to support resources, 'Bundle Accessors' feature should be enabled.",
                severity: .error
            ))
        )
    }

    func test_lint_when_framework_has_resources() async throws {
        let temporaryPath = try temporaryPath()
        let path = temporaryPath.appending(component: "Image.png")
        let element = ResourceFileElement.file(path: path)

        let staticFramework = Target.test(product: .staticFramework, resources: .init([element]))
        let dynamicFramework = Target.test(product: .framework, resources: .init([element]))

        let staticFrameworkResult = try await subject.lint(
            target: staticFramework,
            options: .test()
        )
        XCTAssertFalse(staticFrameworkResult.contains(LintingIssue(
            reason: "Target \(staticFramework.name) cannot contain resources. For \(staticFramework.product) targets to support resources, 'Bundle Accessors' feature should be enabled.",
            severity: .error
        )))

        let dynamicFrameworkResult = try await subject.lint(
            target: dynamicFramework,
            options: .test()
        )
        XCTAssertFalse(dynamicFrameworkResult.contains(LintingIssue(
            reason: "Target \(dynamicFramework.name) cannot contain resources. For \(dynamicFramework.product) targets to support resources, 'Bundle Accessors' feature should be enabled.",
            severity: .error
        )))
    }

    func test_lint_when_macos_bundle_has_no_sources() async throws {
        // Given
        let bundle = Target.empty(
            destinations: .macOS,
            product: .bundle,
            sources: [],
            resources: .init([])
        )

        // When
        let result = try await subject.lint(target: bundle, options: .test())

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_valid_ios_bundle() async throws {
        // Given
        let bundle = Target.empty(
            destinations: .iOS,
            product: .bundle,
            resources: .init(
                [
                    .file(path: "/path/to/some/asset.png"),
                ]
            )
        )

        // When
        let result = try await subject.lint(target: bundle, options: .test())

        // Then
        XCTAssertTrue(result.isEmpty)
    }

    func test_lint_when_deployment_target_version_is_valid() async throws {
        let validVersions = ["10.0", "9.0.1"]
        for version in validVersions {
            // Given
            let target = Target.test(platform: .macOS, deploymentTarget: .macOS(version))

            // When
            let got = try await subject.lint(target: target, options: .test())

            // Then
            XCTAssertFalse(got.contains(LintingIssue(reason: "The version of deployment target is incorrect", severity: .error)))
        }
    }

    func test_lint_when_visionos_iPad_designed_deployment_target_is_valid() async throws {
        let targets = [
            Target(
                name: "visionOS",
                destinations: [.appleVision],
                product: .app,
                productName: "visionOS",
                bundleId: "dev.tuist.visionOS",
                deploymentTargets: .visionOS("1.0"),
                filesGroup: .group(name: "Project")
            ),
            Target(
                name: "iPadVision",
                destinations: [.iPhone, .iPad, .appleVisionWithiPadDesign],
                product: .app,
                productName: "visionOS",
                bundleId: "dev.tuist.visionOS",
                deploymentTargets: .init(iOS: "16.0", visionOS: "1.0"),
                filesGroup: .group(name: "Project")
            ),
        ]

        for target in targets {
            let got = try await subject.lint(target: target, options: .test())

            // Then
            XCTAssertFalse(got.contains(LintingIssue(
                reason: "Found an inconsistency between target destinations `[XcodeGraph.Destination.appleVisionWithiPadDesign, XcodeGraph.Destination.iPad, XcodeGraph.Destination.iPhone]` and deployment target `visionOS`",
                severity: .error
            )))
        }
    }

    func test_lint_when_deployment_target_version_is_invalid() async throws {
        let validVersions = ["tuist", "tuist9.0.1", "1.0tuist", "10_0", "1_1_3"]
        for version in validVersions {
            // Given
            let target = Target.test(platform: .macOS, deploymentTarget: .macOS(version))

            // When
            let got = try await subject.lint(target: target, options: .test())

            // Then
            XCTAssertTrue(got.contains(LintingIssue(reason: "The version of deployment target is incorrect", severity: .error)))
        }
    }

    func test_lint_when_target_platform_and_deployment_target_property_mismatch() async throws {
        let invalidCombinations: [(Platform, DeploymentTargets)] = [
            (.iOS, .macOS("10.0.0")),
            (.watchOS, .macOS("10.0.0")),
            (.macOS, .watchOS("10.0.0")),
            (.tvOS, .macOS("10.0.0")),
        ]
        for combinations in invalidCombinations {
            // Given
            let target = Target.test(platform: combinations.0, deploymentTarget: combinations.1)

            // When
            let got = try await subject.lint(target: target, options: .test())

            let expectedPlatform = try XCTUnwrap(combinations.1.configuredVersions.first?.platform.caseValue)
            // Then
            XCTAssertTrue(got.contains(LintingIssue(
                reason: "Found deployment platforms (\(expectedPlatform)) missing corresponding destination",
                severity: .error
            )))
        }
    }

    func test_lint_invalidProductPlatformCombinations() async throws {
        // Given
        let invalidTargets: [Target] = [
            .empty(name: "WatchApp_for_iOS", destinations: .iOS, product: .watch2App),
            .empty(name: "Watch2Extension_for_iOS", destinations: .iOS, product: .watch2Extension),
        ]

        // When
        let got = try await invalidTargets
            .concurrentMap { try await self.subject.lint(target: $0, options: .test()) }
            .flatMap { $0 }

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

    func test_lint_when_target_has_duplicate_dependencies_specified() async throws {
        let testDependency: TargetDependency = .sdk(name: "libc++.tbd", status: .optional)

        // Given
        let target = Target.test(dependencies: .init(repeating: testDependency, count: 2))

        // When
        let got = try await subject.lint(target: target, options: .test())

        // Then
        XCTAssertTrue(got.contains(LintingIssue(
            reason: "Target '\(target.name)' has duplicate sdk dependency specified: 'libc++.tbd'",
            severity: .warning
        )))
    }

    func test_lint_when_target_has_non_existing_core_data_models() async throws {
        // Given
        let path = try temporaryPath()
        let dataModelPath = path.appending(component: "Model.xcdatamodeld")
        let target = Target.test(coreDataModels: [
            CoreDataModel(path: dataModelPath, versions: [], currentVersion: "1.0.0"),
        ])

        // When
        let got = try await subject.lint(target: target, options: .test())

        // Then
        XCTAssertTrue(got.contains(LintingIssue(
            reason: "The Core Data model at path \(dataModelPath.pathString) does not exist",
            severity: .error
        )))
    }

    func test_lint_when_target_has_core_data_models_with_default_versions_that_dont_exist() async throws {
        // Given
        let path = try temporaryPath()
        let dataModelPath = path.appending(component: "Model.xcdatamodeld")
        try FileHandler.shared.createFolder(dataModelPath)

        let target = Target.test(coreDataModels: [
            CoreDataModel(path: dataModelPath, versions: [], currentVersion: "1.0.0"),
        ])

        // When
        let got = try await subject.lint(target: target, options: .test())

        // Then
        XCTAssertTrue(got.contains(LintingIssue(
            reason: "The default version of the Core Data model at path \(dataModelPath.pathString), 1.0.0, does not exist. There should be a file at \(dataModelPath.appending(component: "1.0.0.xcdatamodel").pathString)",
            severity: .error
        )))
    }

    func test_lint_when_target_has_valid_codegen_sources() async throws {
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
        let got = try await subject.lint(target: target, options: .test())

        // Then
        XCTAssertTrue(got.contains(LintingIssue(
            reason: "Target '\(target.name)' has a source file at path \(target.sources[1].path) with unsupported `codeGen` attributes. Only intentdefinition and mlmodel are known to support this.",
            severity: .warning
        )))
    }

    func test_lint_when_target_has_invalid_on_demand_resources_tags() async throws {
        // Given
        let target = Target.empty(
            onDemandResourcesTags: .init(
                initialInstall: ["tag1", "tag2"],
                prefetchOrder: ["tag2", "tag3"]
            )
        )

        // When
        let got = try await subject.lint(target: target, options: .test())

        // Then
        XCTAssertTrue(got.contains(LintingIssue(
            reason: "Prefetched Order Tag \"tag2\" is already assigned to Initial Install Tags category for the target \(target.name) and will be ignored by Xcode",
            severity: .warning
        )))
    }
}
