import XcodeProj

extension XCWorkspaceDataElement {
    static func test(relativePath: String) -> XCWorkspaceDataElement {
        .file(XCWorkspaceDataFileRef(location: .group(relativePath)))
    }
}
