import Path
import TuistSupport
import XcodeProj
import XCTest

extension TuistAcceptanceTestCase {
    private func headers(
        for productName: String,
        destination: String
    ) async throws -> [AbsolutePath] {
        let productPath = try await productPath(for: productName, destination: destination)
        return try await fileSystem.glob(directory: productPath, include: ["**/*.h"]).collect()
    }

    public func productPath(
        for name: String,
        destination: String
    ) async throws -> AbsolutePath {
        let products = try await fileSystem.glob(
            directory: derivedDataPath,
            include: ["**/Build/**/Products/\(destination)/\(name)/"]
        ).collect()
        return try XCTUnwrap(
            products.first
        )
    }

    public func XCTUnwrapTarget(
        _ targetName: String,
        in xcodeproj: XcodeProj,
        file: StaticString = #file,
        line: UInt = #line
    ) throws -> PBXTarget {
        let targets = xcodeproj.pbxproj.projects.flatMap(\.targets)
        guard let target = targets.first(where: { $0.name == targetName })
        else {
            XCTFail(
                "Target \(targetName) doesn't exist in any of the projects' targets of the workspace",
                file: file,
                line: line
            )
            throw XCTUnwrapError.nilValueDetected
        }

        return target
    }

    public func XCTAssertProductWithDestinationDoesNotContainHeaders(
        _ product: String,
        destination: String,
        file: StaticString = #file,
        line: UInt = #line
    ) async throws {
        if try await !headers(for: product, destination: destination).isEmpty {
            XCTFail("Product with name \(product) and destination \(destination) contains headers", file: file, line: line)
        }
    }

    public func XCTAssertFrameworkEmbedded(
        _ framework: String,
        by targetName: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try XCTUnwrapTarget(targetName, in: xcodeproj)

        let xcframeworkDependencies = target.embedFrameworksBuildPhases()
            .filter { $0.dstSubfolderSpec == .frameworks }
            .map(\.files)
            .compactMap { $0 }
            .flatMap { $0 }
            .compactMap(\.file?.nameOrPath)
            .filter { $0.contains(".framework") }
        guard xcframeworkDependencies.contains("\(framework).framework")
        else {
            XCTFail(
                "Target \(targetName) doesn't embed the framework \(framework)",
                file: file,
                line: line
            )
            return
        }
    }

    /// Given a framework name and a target, it asserts that a framework is configured to be embedded.
    /// - Parameters:
    ///   - framework: Name of the framework without the extension.
    ///   - targetName: Name of the target.
    public func XCTAssertFrameworkNotEmbedded(
        _ framework: String,
        by targetName: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)
        let target = try XCTUnwrapTarget(targetName, in: xcodeproj)

        let embededFrameworks = target.embedFrameworksBuildPhases()
            .filter { $0.dstSubfolderSpec == .frameworks }
            .map(\.files)
            .compactMap { $0 }
            .flatMap { $0 }
            .compactMap(\.file?.nameOrPath)
            .filter { $0.contains(".framework") }

        if embededFrameworks.contains("\(framework).framework") {
            XCTFail(
                "Target \(targetName) embeds the framework \(framework)",
                file: file,
                line: line
            )
            return
        }
    }

    /// Asserts that a simulated location is contained in a specific testable target.
    /// - Parameters:
    ///   - xcodeprojPath: A specific `.xcodeproj` file path.
    ///   - scheme: A specific scheme name.
    ///   - testTarget: A specific test target name.
    ///   - simulatedLocation: A simulated location. This value can be passed a `location string` or a `GPX filename`.
    ///   For example, "Rio de Janeiro, Brazil" or "Grand Canyon.gpx".
    public func XCTAssertContainsSimulatedLocation(
        xcodeprojPath: AbsolutePath,
        scheme: String,
        testTarget: String,
        simulatedLocation: String,
        file: StaticString = #file,
        line: UInt = #line
    ) throws {
        let xcodeproj = try XcodeProj(pathString: xcodeprojPath.pathString)

        guard let scheme = xcodeproj.sharedData?.schemes
            .filter({ $0.name == scheme })
            .first
        else {
            XCTFail(
                "The '\(scheme)' scheme doesn't exist.",
                file: file,
                line: line
            )
            return
        }

        guard let testableTarget = scheme.testAction?.testables
            .filter({ $0.buildableReference.blueprintName == testTarget })
            .first
        else {
            XCTFail(
                "The '\(testTarget)' testable target doesn't exist.",
                file: file,
                line: line
            )
            return
        }

        XCTAssertEqual(
            testableTarget.locationScenarioReference?.identifier.contains(simulatedLocation),
            true,
            "The '\(testableTarget)' testable target doesn't have simulated location set.",
            file: file,
            line: line
        )
    }
}
