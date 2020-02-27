
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension GeneratedSchemeDescriptor {
    static func test(name: String, shared: Bool) -> GeneratedSchemeDescriptor {
        let scheme = XCScheme(name: name, lastUpgradeVersion: "1131", version: "1")
        return GeneratedSchemeDescriptor(scheme: scheme, shared: shared)
    }
}
