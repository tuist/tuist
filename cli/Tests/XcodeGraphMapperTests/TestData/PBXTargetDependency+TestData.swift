import XcodeProj

extension PBXTargetDependency {
    static func test(
        name: String? = "App",
        target: PBXTarget? = nil,
        targetProxy: PBXContainerItemProxy? = nil,
        platformFilter: String? = nil,
        platformFilters: [String]? = nil
    ) -> PBXTargetDependency {
        PBXTargetDependency(
            name: name,
            platformFilter: platformFilter,
            platformFilters: platformFilters,
            target: target,
            targetProxy: targetProxy
        )
    }
}
