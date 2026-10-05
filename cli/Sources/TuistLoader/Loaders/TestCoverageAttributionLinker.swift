import Foundation
import Path
import TuistCore
import TuistLogging
import XcodeGraph

public enum TestCoverageAttributionLinkerError: FatalError, Equatable {
    case missingPackageManifest
    case missingPackage(packageManifestPath: AbsolutePath)

    public var type: ErrorType { .abort }

    public var description: String {
        let declaration =
            "`.package(url: \"\(TestCoverageAttributionLinker.packageURL)\", .upToNextMinor(from: \"\(TestCoverageAttributionLinker.minimumVersion)\"))`"
        switch self {
        case .missingPackageManifest:
            return "`testInsights.coverage.attributeToTests` links TestCoverageAttribution into your unit test targets, but the project has no `Tuist/Package.swift`. Create one that declares \(declaration) and run `tuist install`."
        case let .missingPackage(packageManifestPath):
            return "`testInsights.coverage.attributeToTests` links TestCoverageAttribution into your unit test targets, but it is not an external dependency. Add \(declaration) to the dependencies of \(packageManifestPath.pathString) and run `tuist install`."
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
        var packageSettings = packageSettings
        packageSettings.productTypes[Self.productName] = .framework
        packageSettings.productTypes[Self.observerTargetName] = .framework
        return packageSettings
    }

    public func link(
        projects: [XcodeGraph.Project],
        externalDependencies: [String: [XcodeGraph.TargetDependency]],
        packageManifestPath: AbsolutePath?
    ) throws -> [XcodeGraph.Project] {
        guard let packageManifestPath else { throw TestCoverageAttributionLinkerError.missingPackageManifest }
        guard let dependencies = externalDependencies[Self.productName] else {
            throw TestCoverageAttributionLinkerError.missingPackage(packageManifestPath: packageManifestPath)
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
