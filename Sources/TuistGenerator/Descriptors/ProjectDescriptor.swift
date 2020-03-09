import Basic
import Foundation
import XcodeProj

public class ProjectDescriptor {
    /// Path to the project
    public var path: AbsolutePath

    /// Path to the xcodeproj file
    public var xcodeprojPath: AbsolutePath

    public var xcodeProj: XcodeProj
    public var schemeDescriptors: [SchemeDescriptor]
    public var sideEffectDescriptors: [SideEffectDescriptor]

    public init(path: AbsolutePath,
                xcodeprojPath: AbsolutePath,
                xcodeProj: XcodeProj,
                schemeDescriptors: [SchemeDescriptor],
                sideEffectDescriptors: [SideEffectDescriptor]) {
        self.path = path
        self.xcodeprojPath = xcodeprojPath
        self.xcodeProj = xcodeProj
        self.schemeDescriptors = schemeDescriptors
        self.sideEffectDescriptors = sideEffectDescriptors
    }
}
