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

    public init(xcScheme: XCScheme, shared: Bool) {
        self.xcScheme = xcScheme
        self.shared = shared
    }
}
