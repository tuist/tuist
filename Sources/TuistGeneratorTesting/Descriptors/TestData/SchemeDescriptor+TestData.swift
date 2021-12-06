import Foundation
import TSCBasic
import XcodeProj
@testable import TuistGenerator

extension SchemeDescriptor {
    public static func test(name: String, shared: Bool, hidden: Bool = false) -> SchemeDescriptor {
        let scheme = XCScheme(name: name, lastUpgradeVersion: "1131", version: "1")
        return SchemeDescriptor(xcScheme: scheme, shared: shared, hidden: hidden)
    }
}
