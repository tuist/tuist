
import Basic
import Foundation
import XcodeProj
@testable import TuistGenerator

extension SchemeDescriptor {
    static func test(name: String, shared: Bool) -> SchemeDescriptor {
        let scheme = XCScheme(name: name, lastUpgradeVersion: "1131", version: "1")
        return SchemeDescriptor(scheme: scheme, shared: shared)
    }
}
