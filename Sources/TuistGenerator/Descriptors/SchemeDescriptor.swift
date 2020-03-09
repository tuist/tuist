import Foundation
import XcodeProj

public struct SchemeDescriptor {
    public var xcScheme: XCScheme
    public var shared: Bool

    public init(xcScheme: XCScheme, shared: Bool) {
        self.xcScheme = xcScheme
        self.shared = shared
    }
}
