import Foundation

/// A protocol conformed by objects that can return a Xcode representation of its value.
public protocol XcodeRepresentable {
    associatedtype Value

    /// Xcode value.
    var xcodeValue: Value { get }
}
