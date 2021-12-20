import ProjectDescription

extension Project {
    public static func app(
        name: String,
        dependencies: [TargetDependency]
    ) -> Project {
        Project(
            name: name,
            organizationName: "tuist.io",
            settings: Settings.default,
            targets: [
                .main(
                    name: name,
                    product: .app,
                    dependencies: dependencies,
                    resources: ["Resources/**"]
                ),
                .test(name: name),
            ],
            schemes: [
                .scheme(
                    name: name,
                    mainTargetName: name,
                    testTargetName: "\(name)Tests"
                ),
            ]
        )
    }

    public static func framework(
        name: String,
        dependencies: [TargetDependency]
    ) -> Project {
        Project(
            name: name,
            organizationName: "tuist.io",
            settings: Settings.default,
            targets: [
                .main(
                    name: name,
                    product: .framework,
                    dependencies: dependencies
                ),
                .test(name: name),
            ],
            schemes: [
                .scheme(
                    name: name,
                    mainTargetName: name,
                    testTargetName: "\(name)Tests"
                ),
            ]
        )
    }
}

extension Target {
    public static func main(
        name: String,
        product: Product,
        dependencies: [TargetDependency],
        resources: ResourceFileElements? = nil
    ) -> Target {
        Target(
            name: name,
            platform: .iOS,
            product: product,
            bundleId: "tuist.io.\(name)",
            deploymentTarget: .deploymentTarget,
            infoPlist: .default,
            sources: ["Sources/**"],
            resources: resources,
            dependencies: dependencies
        )
    }

    public static func test(
        name: String
    ) -> Target {
        Target(
            name: "\(name)Tests",
            platform: .iOS,
            product: .unitTests,
            bundleId: "tuist.io..\(name)Tests",
            infoPlist: .default,
            sources: ["Tests/**"],
            dependencies: [.target(name: "\(name)")]
        )
    }
}

extension DeploymentTarget {
    static var deploymentTarget: DeploymentTarget {
        .iOS(
            targetVersion: "11.0",
            devices: [.iphone]
        )
    }
}

extension Scheme {
    static func scheme(
        name: String,
        mainTargetName: String,
        testTargetName: String
    ) -> Scheme {
        let main = TargetReference(
            projectPath: nil,
            target: mainTargetName
        )
        let test = TargetReference(
            projectPath: nil,
            target: testTargetName
        )

        return Scheme(
            name: name,
            shared: true,
            buildAction: .buildAction(targets: [
                main,
            ]),
            testAction: .targets(
                [
                    TestableTarget(target: test),
                ],
                configuration: "debug"
            ),
            runAction: .runAction(
                configuration: "debug",
                executable: main
            ),
            archiveAction: .archiveAction(
                configuration: "release"
            ),
            profileAction: .profileAction(
                configuration: "release",
                executable: main
            ),
            analyzeAction: .analyzeAction(
                configuration: "debug"
            )
        )
    }
}

extension Settings {
    public static let `default`: Settings = .settings(
        base: [:],
        configurations: [
            .debug(
                name: "debug",
                settings: [
                    "OTHER_SWIFT_FLAGS": [
                        "-DDEBUG_MACRO",
                    ],
                ]
            ),
            .release(
                name: "release",
                settings: [
                    "OTHER_SWIFT_FLAGS": [
                        "-DRELEASE_MARCO",
                    ],
                ]
            ),
        ],
        defaultSettings: .recommended
    )
}
