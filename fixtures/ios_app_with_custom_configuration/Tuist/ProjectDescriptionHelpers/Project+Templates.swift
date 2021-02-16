import ProjectDescription

extension Project {
    public static func app(
        name: String,
        dependencies: [TargetDependency]
    ) -> Project {
        return Project(
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
                .test(name: name)
            ],
            schemes: [
                .scheme(
                    name: name,
                    mainTargetName: name,
                    testTargetName: "\(name)Tests"
                )
            ]
        )
    }

    public static func framework(
        name: String,
        dependencies: [TargetDependency]
    ) -> Project {
        return Project(
            name: name,
            organizationName: "tuist.io",
            settings: Settings.default,
            targets: [
                .main(
                    name: name,
                    product: .framework,
                    dependencies: dependencies
                ),
                .test(name: name)
            ],
            schemes: [
                .scheme(
                    name: name,
                    mainTargetName: name,
                    testTargetName: "\(name)Tests"
                )
            ]
        )
    }
}

public extension Target {
    static func main(
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

    static func test(
        name: String
    ) -> Target {
        return Target(
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
        return .iOS(
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
            buildAction: BuildAction(targets: [
                main
            ]),
            testAction: TestAction(
                targets: [
                    TestableTarget(target: test)
                ],
                configurationName: "debug"
            ),
            runAction: RunAction(
                configurationName: "debug",
                executable: main
            ),
            archiveAction: ArchiveAction(
                configurationName: "release"
            ),
            profileAction: ProfileAction(
                configurationName: "release",
                executable: main
            ),
            analyzeAction: AnalyzeAction(
                configurationName: "debug"
            )
        )
    }
}

extension Settings {
    public static let `default` = Settings(
        base: [:],
        configurations: [
            .debug(
                name: "debug",
                settings: [
                    "OTHER_SWIFT_FLAGS": [
                        "-DDEBUG_MACRO"
                    ]
                ]
            ),
            .release(
                name: "release",
                settings: [
                    "OTHER_SWIFT_FLAGS": [
                        "-DRELEASE_MARCO"
                    ]
                ]
            )
        ],
        defaultSettings: .recommended
    )
}
