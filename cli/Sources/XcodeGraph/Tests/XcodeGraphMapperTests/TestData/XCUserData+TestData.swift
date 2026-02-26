import XcodeProj

/// Tests?
extension XCUserData {
    static func test(
        userName: String = "user",
        schemes: [XCScheme] = [],
        schemeManagement: XCSchemeManagement? = XCSchemeManagement(
            schemeUserState: [
                XCSchemeManagement.UserStateScheme(
                    name: "App.xcscheme",
                    shared: true,
                    orderHint: 0,
                    isShown: true
                ),
            ],
            suppressBuildableAutocreation: nil
        )
    ) -> XCUserData {
        XCUserData(
            userName: userName,
            schemes: schemes,
            breakpoints: nil,
            schemeManagement: schemeManagement
        )
    }
}
