import Path
import Testing
import TuistCore
import TuistSupport
import XcodeGraph

@testable import TuistLoader

struct TestCoverageAttributionLinkerTests {
    private let subject = TestCoverageAttributionLinker()
    private let attribution: XcodeGraph.TargetDependency = .project(
        target: "TestCoverageAttribution",
        path: "/project/Tuist/.build/checkouts/TestCoverageAttribution"
    )

    @Test func link_addsThePackageToUnitTestTargetsOnly() throws {
        // Given
        let project = Project.test(targets: [
            .test(name: "App", product: .app),
            .test(name: "Framework", product: .framework),
            .test(name: "AppTests", product: .unitTests, dependencies: [.target(name: "App")]),
            .test(name: "FrameworkTests", product: .unitTests),
            .test(name: "AppUITests", product: .uiTests),
        ])

        // When
        let got = try subject.link(
            projects: [project],
            externalDependencies: ["TestCoverageAttribution": [attribution]],
            packageManifestPath: "/project/Tuist/Package.swift"
        )

        // Then
        let targets = try #require(got.first).targets
        #expect(targets["App"]?.dependencies == [])
        #expect(targets["Framework"]?.dependencies == [])
        #expect(targets["AppTests"]?.dependencies == [.target(name: "App"), attribution])
        #expect(targets["FrameworkTests"]?.dependencies == [attribution])
        #expect(targets["AppUITests"]?.dependencies == [])
    }

    @Test func link_doesNotDuplicateADependencyTheTargetAlreadyDeclares() throws {
        // Given
        let project = Project.test(targets: [
            .test(name: "AppTests", product: .unitTests, dependencies: [attribution]),
        ])

        // When
        let got = try subject.link(
            projects: [project],
            externalDependencies: ["TestCoverageAttribution": [attribution]],
            packageManifestPath: "/project/Tuist/Package.swift"
        )

        // Then
        #expect(try #require(got.first).targets["AppTests"]?.dependencies == [attribution])
    }

    @Test func link_throwsWhenThereIsNoPackageManifest() {
        #expect(throws: TestCoverageAttributionLinkerError.missingPackageManifest) {
            try subject.link(projects: [.test()], externalDependencies: [:], packageManifestPath: nil)
        }
    }

    @Test func link_throwsWhenThePackageIsNotDeclared() {
        #expect(throws: TestCoverageAttributionLinkerError.missingPackage(packageManifestPath: "/project/Package.swift")) {
            try subject.link(
                projects: [.test()],
                externalDependencies: ["Alamofire": []],
                packageManifestPath: "/project/Package.swift"
            )
        }
    }

    @Test func packageSettings_makesThePackageTargetsDynamicFrameworks() {
        // Given
        let packageSettings = TuistCore.PackageSettings.test(
            productTypes: ["TestCoverageAttribution": .staticFramework, "Alamofire": .staticLibrary],
            baseProductType: .staticFramework
        )

        // When
        let got = subject.packageSettings(packageSettings)

        // Then
        #expect(got.productTypes == [
            "TestCoverageAttribution": .framework,
            "TestCoverageAttributionObserver": .framework,
            "Alamofire": .staticLibrary,
        ])
        #expect(got.baseProductType == .staticFramework)
    }
}
