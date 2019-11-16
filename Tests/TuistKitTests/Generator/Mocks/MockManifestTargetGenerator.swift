
import Basic
import Foundation
import TuistCore
import TuistGenerator
@testable import TuistKit

final class MockManifestTargetGenerator: ManifestTargetGenerating {
    var generateManifestTargetStub: ((String, AbsolutePath) throws -> Target)?
    func generateManifestTarget(for project: String, at path: AbsolutePath) throws -> Target {
        return try generateManifestTargetStub?(project, path) ?? dummyTarget(name: "\(project)-Manifest")
    }

    private func dummyTarget(name: String) -> Target {
        return Target(name: name,
                      platform: .iOS,
                      product: .framework,
                      productName: name,
                      bundleId: "io.tuist.testing",
                      infoPlist: nil,
                      filesGroup: .group(name: "Manifest"))
    }
}
