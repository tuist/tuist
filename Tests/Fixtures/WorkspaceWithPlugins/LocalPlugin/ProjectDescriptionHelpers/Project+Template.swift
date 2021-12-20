import ProjectDescription

extension Target {
    public static func app(name: String, dependencies: [TargetDependency] = []) -> Target {
        Target(
            name: name,
            platform: .iOS,
            product: .app,
            bundleId: .bundleId(for: name),
            infoPlist: .default,
            sources: ["Sources/**"],
            resources: [],
            dependencies: dependencies
        )
    }

    public static func framework(name: String, dependencies: [TargetDependency] = []) -> Target {
        Target(
            name: name,
            platform: .iOS,
            product: .framework,
            bundleId: .bundleId(for: name),
            infoPlist: .default,
            sources: ["Sources/**"],
            resources: [],
            dependencies: dependencies
        )
    }
}

extension String {
    /// Returns a canonical bundle Id for the target with the
    /// given name
    /// - parameter target: the name of the target
    /// - returns: the bundle id for the given target
    public static func bundleId(for target: String) -> String {
        "io.tuist.\(target)"
    }
}
