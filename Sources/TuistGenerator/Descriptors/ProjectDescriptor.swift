import Foundation
import TSCBasic
import TuistCore
import XcodeProj

/// Project Descriptor
///
/// Contains the information needed to generate a project.
///
/// Can be used in conjunction with `XcodeProjWriter` to
/// generate an `.xcodeproj` file.
///
/// - seealso: `XcodeProjWriter`
public struct ProjectDescriptor {
    /// Path to the project
    public var path: AbsolutePath

    /// Path to the xcodeproj file
    public var xcodeprojPath: AbsolutePath

    /// The XcodeProj representation of this project
    public var xcodeProj: XcodeProj

    /// The scheme descriptors of all the schemes within this project
    public var schemeDescriptors: [SchemeDescriptor]

    /// The side effects required for generating this project
    public var sideEffectDescriptors: [SideEffectDescriptor]

    public init(
        path: AbsolutePath,
        xcodeprojPath: AbsolutePath,
        xcodeProj: XcodeProj,
        schemeDescriptors: [SchemeDescriptor],
        sideEffectDescriptors: [SideEffectDescriptor]
    ) {
        self.path = path
        self.xcodeprojPath = xcodeprojPath
        self.xcodeProj = xcodeProj
        self.schemeDescriptors = schemeDescriptors
        self.sideEffectDescriptors = sideEffectDescriptors
    }
}
