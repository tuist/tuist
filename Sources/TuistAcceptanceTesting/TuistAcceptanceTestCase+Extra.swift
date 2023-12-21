import TSCBasic
import TuistSupport
import XcodeProj
import XCTest

extension TuistAcceptanceTestCase {
    private func headers(
        for productName: String,
        destination: String
    ) throws -> [AbsolutePath] {
        let productPath = try productPath(for: productName, destination: destination)
        return FileHandler.shared.glob(productPath, glob: "**/*.h")
    }

    public func productPath(
        for name: String,
        destination: String
    ) throws -> AbsolutePath {
        try XCTUnwrap(
            FileHandler.shared.glob(derivedDataPath, glob: "**/Build/**/Products/\(destination)/\(name.components(separatedBy: ".").first ?? name)/\(name)/").first
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
    ) throws {
        if try !headers(for: product, destination: destination).isEmpty {
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
                "Target \(targetName) doesn't link the framework \(framework)",
                file: file,
                line: line
            )
            return
        }
    }
}
