import XcodeProj

extension XCConfigurationList {
    static func test(
        buildConfigurations: [XCBuildConfiguration] = [],
        defaultConfigurationName: String = "Release",
        defaultConfigurationIsVisible: Bool = false
    ) -> XCConfigurationList {
        XCConfigurationList(
            buildConfigurations: buildConfigurations,
            defaultConfigurationName: defaultConfigurationName,
            defaultConfigurationIsVisible: defaultConfigurationIsVisible
        )
    }
}
