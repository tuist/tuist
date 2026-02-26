import XcodeProj

extension XCWorkspace {
    static func test(
        files: [String] = [
            "App/MainApp.xcodeproj",
            "Framework1/Framework1.xcodeproj",
            "StaticFramework1/StaticFramework1.xcodeproj",
        ],
        path: String
    ) -> XCWorkspace {
        let children = files.map { path in
            XCWorkspaceDataElement.file(XCWorkspaceDataFileRef(location: .group(path)))
        }
        return XCWorkspace(data: XCWorkspaceData(children: children), path: .init(path))
    }

    static func test(withElements elements: [XCWorkspaceDataElement], path: String) -> XCWorkspace {
        let data = XCWorkspaceData(children: elements)
        return XCWorkspace(data: data, path: .init(path))
    }
}
