import Basic
import Foundation
import SPMUtility

/// Contains the versions of some system components that Tuist depends on (e.g. Xcode)
/// Since versions won't change during the execution of Tuist, we load them into an instance
/// of this struct, and pass them down to the utilities that might need to access them.
public struct Versions {
    /// Version of Xcode
    public let xcode: Version

    /// Version of Swift
    public let swift: Version

    public init(xcode: Version, swift: Version) {
        self.xcode = xcode
        self.swift = swift
    }
}
