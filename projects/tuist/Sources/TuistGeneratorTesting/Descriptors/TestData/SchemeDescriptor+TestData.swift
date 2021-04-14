import Foundation
import TSCBasic
import XcodeProj
@testable import TuistGenerator

public extension SchemeDescriptor {
    static func test(name: String, shared: Bool) -> SchemeDescriptor {
        let scheme = XCScheme(name: name, lastUpgradeVersion: "1131", version: "1")
        return SchemeDescriptor(xcScheme: scheme, shared: shared)
    }
}
