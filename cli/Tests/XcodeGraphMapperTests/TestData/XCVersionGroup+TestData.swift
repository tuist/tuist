import XcodeProj

extension XCVersionGroup {
    static func test(
        currentVersion: PBXFileReference? = nil,
        children: [PBXFileElement] = [],
        path: String = "DefaultGroup",
        sourceTree: PBXSourceTree = .group,
        versionGroupType: String? = nil,
        name: String? = nil,
        includeInIndex: Bool? = nil,
        wrapsLines: Bool? = nil,
        usesTabs: Bool? = nil,
        indentWidth: UInt? = nil,
        tabWidth: UInt? = nil,
        pbxProj _: PBXProj
    ) -> XCVersionGroup {
        let group = XCVersionGroup(
            currentVersion: currentVersion,
            path: path,
            name: name,
            sourceTree: sourceTree,
            versionGroupType: versionGroupType,
            includeInIndex: includeInIndex,
            wrapsLines: wrapsLines,
            usesTabs: usesTabs,
            indentWidth: indentWidth,
            tabWidth: tabWidth
        )

        group.children = children
        return group
    }
}
