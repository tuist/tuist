import Foundation
import XcodeProj

public struct SchemeDescriptor {
    public var scheme: XCScheme
    public var shared: Bool

    public init(scheme: XCScheme, shared: Bool) {
        self.scheme = scheme
        self.shared = shared
    }
}
