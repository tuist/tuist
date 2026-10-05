import Foundation
import TuistCore
import TuistLogging
import XcodeGraph

public enum TestCoverageAttributionLinkerError: FatalError, Equatable {
    case missingPackageManifest
    case missingPackage

    public var type: ErrorType { .abort }

    public var description: String {
        let declaration =
            "`.package(url: \"\(TestCoverageAttributionLinker.packageURL)\", .upToNextMinor(from: \"\(TestCoverageAttributionLinker.minimumVersion)\"))`"
        switch self {
        case .missingPackageManifest:
            return "`testInsights.coverage.attributeToTests` links TestCoverageAttribution into your unit test targets, but the project has no `Tuist/Package.swift`. Create one that declares \(declaration) and run `tuist install`."
        case .missingPackage:
            return "`testInsights.coverage.attributeToTests` links TestCoverageAttribution into your unit test targets, but it is not an external dependency. Add \(declaration) to the dependencies of `Tuist/Package.swift` and run `tuist install`."
        }
    }
}

/// Links [TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) into the unit test targets of
/// generated projects when `testInsights.coverage.attributeToTests` is on.
///
/// UI test targets are left out: their tests drive the app in another process, which the observer can't see.
public struct TestCoverageAttributionLinker {
    static let packageURL = "https://github.com/tuist/TestCoverageAttribution"
    static let minimumVersion = "0.1.1"
    static let productName = "TestCoverageAttribution"
    static let observerTargetName = "TestCoverageAttributionObserver"

    public init() {}

    /// Makes both of the package's targets dynamic frameworks. Linked statically into a test target that references
    /// nothing in the package, as XCTest-only targets do, the linker drops the observer.
    public func packageSettings(_ packageSettings: TuistCore.PackageSettings) -> TuistCore.PackageSettings {
        TuistCore.PackageSettings(
            productTypes: packageSettings.productTypes.merging(
                [Self.productName: .framework, Self.observerTargetName: .framework],
                uniquingKeysWith: { _, forced in forced }
            ),
            baseProductType: packageSettings.baseProductType,
            productDestinations: packageSettings.productDestinations,
            baseSettings: packageSettings.baseSettings,
            expectedSignatures: packageSettings.expectedSignatures,
            targetSettings: packageSettings.targetSettings,
            projectOptions: packageSettings.projectOptions,
            includeLocalPackageTestTargets: packageSettings.includeLocalPackageTestTargets
        )
    }

    public func link(
        projects: [XcodeGraph.Project],
        externalDependencies: [String: [XcodeGraph.TargetDependency]]?
    ) throws -> [XcodeGraph.Project] {
        guard let externalDependencies else { throw TestCoverageAttributionLinkerError.missingPackageManifest }
        guard let dependencies = externalDependencies[Self.productName] else {
            throw TestCoverageAttributionLinkerError.missingPackage
        }
        return projects.map { project in
            var project = project
            project.targets = project.targets.mapValues { target in
                guard target.product == .unitTests else { return target }
                var target = target
                target.dependencies += dependencies.filter { !target.dependencies.contains($0) }
                return target
            }
            return project
        }
    }
}
