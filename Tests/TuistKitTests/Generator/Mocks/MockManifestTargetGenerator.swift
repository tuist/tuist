
import Basic
import Foundation
@testable import TuistKit

class MockManifestTargetGenerator: ManifestTargetGenerating {
    var generateManifestTargetStub: ((String, AbsolutePath) throws -> Target)?
    func generateManifestTarget(for project: String, at path: AbsolutePath) throws -> Target {
        return try generateManifestTargetStub?(project, path) ?? Target.test(name: "\(project)-Manifest")
    }
}
