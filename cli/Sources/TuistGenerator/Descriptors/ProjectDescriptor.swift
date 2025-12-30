import Foundation
import Path
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

#if DEBUG
    extension ProjectDescriptor {
        public static func test(
            path: AbsolutePath = try! AbsolutePath(validating: "/Test"), // swiftlint:disable:this force_try
            xcodeprojPath: AbsolutePath? = nil,
            schemes: [SchemeDescriptor] = [],
            sideEffects: [SideEffectDescriptor] = []
        ) -> ProjectDescriptor {
            let mainGroup = PBXGroup()
            let configurationList = XCConfigurationList()
            let pbxProject = PBXProject(
                name: "Test",
                buildConfigurationList: configurationList,
                compatibilityVersion: "1",
                preferredProjectObjectVersion: nil,
                minimizedProjectReferenceProxies: nil,
                mainGroup: mainGroup
            )
            let pbxproj = PBXProj(
                objectVersion: 70,
                archiveVersion: 10
            )
            pbxproj.add(object: mainGroup)
            pbxproj.add(object: pbxProject)
            pbxproj.add(object: configurationList)
            pbxproj.rootObject = pbxProject
            let xcodeProj = XcodeProj(workspace: XCWorkspace(), pbxproj: pbxproj)
            return ProjectDescriptor(
                path: path,
                xcodeprojPath: xcodeprojPath ?? path.appending(component: "Test.xcodeproj"),
                xcodeProj: xcodeProj,
                schemeDescriptors: schemes,
                sideEffectDescriptors: sideEffects
            )
        }
    }
#endif
