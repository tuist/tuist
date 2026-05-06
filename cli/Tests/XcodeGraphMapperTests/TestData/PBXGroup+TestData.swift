import XcodeProj

extension PBXGroup {
    static func test(
        children: [PBXFileElement] = [],
        sourceTree: PBXSourceTree = .group,
        name: String? = "MainGroup",
        path: String? = "/tmp/TestProject"
    ) -> PBXGroup {
        PBXGroup(
            children: children,
            sourceTree: sourceTree,
            name: name,
            path: path
        )
    }
}
