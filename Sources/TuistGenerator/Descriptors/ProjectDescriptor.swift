import Basic
import Foundation
import XcodeProj

public class ProjectDescriptor {
    /// Path to the project
    public var path: AbsolutePath

    /// Path to the xcodeproj file
    public var xcodeprojPath: AbsolutePath

    public var xcodeProj: XcodeProj
    public var schemes: [SchemeDescriptor]
    public var sideEffects: [SideEffect]

    public init(path: AbsolutePath,
                xcodeprojPath: AbsolutePath,
                xcodeProj: XcodeProj,
                schemes: [SchemeDescriptor],
                sideEffects: [SideEffect]) {
        self.path = path
        self.xcodeprojPath = xcodeprojPath
        self.xcodeProj = xcodeProj
        self.schemes = schemes
        self.sideEffects = sideEffects
    }
}
