import XcodeProj

extension PBXVariantGroup {
    static func mockVariant(
        children: [PBXFileElement] = [],
        sourceTree: PBXSourceTree = .group,
        name: String? = "MainGroup",
        path: String? = "/tmp/TestProject"
    ) -> PBXVariantGroup {
        PBXVariantGroup(
            children: children,
            sourceTree: sourceTree,
            name: name,
            path: path
        )
    }
}
