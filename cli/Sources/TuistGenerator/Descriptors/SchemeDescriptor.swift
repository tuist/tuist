import Foundation
import XcodeProj

/// Scheme Descriptor
///
/// Contains the information needed to generate a scheme.
///
/// When part of a `ProjectDescriptor` or `WorkspaceDescriptor`, it
/// can be used in conjunction with `XcodeProjWriter` to generate
/// an `.xcscheme` file.
///
/// - seealso: `ProjectDescriptor`
/// - seealso: `WorkspaceDescriptor`
/// - seealso: `XcodeProjWriter`
public struct SchemeDescriptor {
    /// The XCScheme scheme representation
    public var xcScheme: XCScheme

    /// The Scheme type shared vs user scheme
    public var shared: Bool

    /// Whether the scheme is hidden or not.
    public var hidden: Bool

    /// The position of the scheme in Xcode's scheme list, ahead of the schemes without one.
    public var orderHint: Int?

    public init(xcScheme: XCScheme, shared: Bool, hidden: Bool, orderHint: Int? = nil) {
        self.xcScheme = xcScheme
        self.shared = shared
        self.hidden = hidden
        self.orderHint = orderHint
    }

    #if DEBUG
        public static func test(name: String, shared: Bool, hidden: Bool = false, orderHint: Int? = nil) -> SchemeDescriptor {
            let scheme = XCScheme(name: name, lastUpgradeVersion: "1131", version: "1")
            return SchemeDescriptor(xcScheme: scheme, shared: shared, hidden: hidden, orderHint: orderHint)
        }
    #endif
}
