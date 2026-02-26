import XcodeProj

extension PBXProject {
    static func test(
        name: String = "MainApp",
        buildConfigurationList: XCConfigurationList,
        compatibilityVersion: String = "Xcode 14.0",
        preferredProjectObjectVersion: Int? = nil,
        minimizedProjectReferenceProxies: Int? = nil,
        mainGroup: PBXGroup,
        developmentRegion: String = "en",
        hasScannedForEncodings: Int = 0,
        knownRegions: [String] = ["Base", "en"],
        productsGroup: PBXGroup? = nil,
        projectDirPath: String = "",
        projects: [[String: PBXFileElement]] = [
            ["B900DB68213936CC004AEC3E": PBXFileReference.test(name: "App", path: "App.xcodeproj")],
        ],
        projectRoots: [String] = [""],
        targets: [PBXTarget] = [],
        attributes: [String: ProjectAttribute] = MockDefaults.defaultProjectAttributes,
        packageReferences: [XCRemoteSwiftPackageReference] = [],
        targetAttributes: [PBXTarget: [String: ProjectAttribute]] = [:]
    ) -> PBXProject {
        PBXProject(
            name: name,
            buildConfigurationList: buildConfigurationList,
            compatibilityVersion: compatibilityVersion,
            preferredProjectObjectVersion: preferredProjectObjectVersion,
            minimizedProjectReferenceProxies: minimizedProjectReferenceProxies,
            mainGroup: mainGroup,
            developmentRegion: developmentRegion,
            hasScannedForEncodings: hasScannedForEncodings,
            knownRegions: knownRegions,
            productsGroup: productsGroup,
            projectDirPath: projectDirPath,
            projects: projects,
            projectRoots: projectRoots,
            targets: targets,
            packages: packageReferences,
            attributes: attributes,
            targetAttributes: targetAttributes
        )
    }
}

//
//
// import XcodeProj
//
// extension PBXProject {
//    static func test(
//        name: String = "MainApp",
//        buildConfigurationList: XCConfigurationList? = nil,
//        compatibilityVersion: String = "Xcode 14.0",
//        mainGroup: PBXGroup? = nil,
//        developmentRegion: String = "en",
//        knownRegions: [String] = ["Base", "en"],
//        productsGroup: PBXGroup? = nil,
//        targets: [PBXTarget]? = nil,
//        attributes: [String: Any] = MockDefaults.defaultProjectAttributes,
//        packageReferences: [XCRemoteSwiftPackageReference] = [],
//        pbxProj: PBXProj
//    ) -> PBXProject {
//        let resolvedMainGroup =
//            mainGroup
//                ?? PBXGroup.test(
//                    children: [],
//                    sourceTree: .group,
//                    name: "MainGroup",
//                    path: "/tmp/TestProject",
//                    pbxProj: pbxProj,
//                    addToMainGroup: false
//                )
//
//        let resolvedBuildConfigList = buildConfigurationList ?? XCConfigurationList.test(proj: pbxProj)
//        pbxProj.add(object: resolvedBuildConfigList)
//
//        if let productsGroup {
//            pbxProj.add(object: productsGroup)
//        }
//
//        let projectRef = PBXFileReference.test(
//            name: "App",
//            path: "App.xcodeproj",
//            pbxProj: pbxProj,
//            addToMainGroup: false
//        ).add(to: pbxProj).addToMainGroup(in: pbxProj)
//
//        let proj = PBXProject(
//            name: name,
//            buildConfigurationList: resolvedBuildConfigList,
//            compatibilityVersion: compatibilityVersion,
//            preferredProjectObjectVersion: nil,
//            minimizedProjectReferenceProxies: nil,
//            mainGroup: resolvedMainGroup,
//            developmentRegion: developmentRegion,
//            hasScannedForEncodings: 0,
//            knownRegions: knownRegions,
//            productsGroup: productsGroup,
//            projectDirPath: "",
//            projects: [["B900DB68213936CC004AEC3E": projectRef]],
//            projectRoots: [""],
//            targets: targets ?? [],
//            packages: packageReferences,
//            attributes: attributes,
//            targetAttributes: [:]
//        )
//
//        pbxProj.add(object: proj)
//        pbxProj.rootObject = proj
//        return proj
//    }
// }
