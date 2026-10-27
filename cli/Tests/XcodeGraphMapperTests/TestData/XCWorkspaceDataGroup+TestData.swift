import XcodeProj

extension XCWorkspaceDataElement {
    static func test(name: String, children: [XCWorkspaceDataElement]) -> XCWorkspaceDataElement {
        .group(XCWorkspaceDataGroup(location: .group(name), name: name, children: children))
    }
}
