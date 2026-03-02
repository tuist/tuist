import XcodeProj

extension PBXFileReference {
    static func test(
        sourceTree: PBXSourceTree = .group,
        name: String? = nil,
        explicitFileType: String? = nil,
        path: String = "AppDelegate.swift",
        lastKnownFileType: String? = "sourcecode.swift",
        includeInIndex: Bool? = nil
    ) -> PBXFileReference {
        PBXFileReference(
            sourceTree: sourceTree,
            name: name,
            explicitFileType: explicitFileType,
            lastKnownFileType: lastKnownFileType,
            path: path,
            includeInIndex: includeInIndex
        )
    }
}
