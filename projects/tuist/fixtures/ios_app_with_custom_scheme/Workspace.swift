import ProjectDescription

let customAppScheme = Scheme(
    name: "Workspace-App",
    shared: true,
    buildAction: .buildAction(
        targets: [
            .project(path: "App", target: "App"),
            .project(path: "Frameworks/Framework1", target: "Framework1"),
        ],
        preActions: [
            ExecutionAction(
                scriptText: "echo pre-action",
                target: .project(path: "App", target: "App")
            ),
        ],
        postActions: [
            ExecutionAction(
                scriptText: "echo post-action",
                target: .project(path: "Frameworks/Framework1", target: "Framework1")
            ),
        ]
    ),
    testAction: TestAction.targets([
        TestableTarget(target: .project(path: "App", target: "AppTests")),
        TestableTarget(target: .project(
            path: "Frameworks/Framework1",
            target: "Framework1Tests"
        )),
        TestableTarget(target: .project(
            path: "Frameworks/Framework2",
            target: "Framework2Tests"
        )),
    ]),
    runAction: .runAction(executable: .project(path: "App", target: "App")),
    archiveAction: .archiveAction(configuration: "Debug", customArchiveName: "Something2")
)

let customAppSchemeWithTestPlans = Scheme(
    name: "Workspace-App-With-TestPlans",
    shared: true,
    buildAction: .buildAction(
        targets: [.project(path: "App", target: "App")],
        preActions: []
    ),
    testAction: TestAction
        .testPlans([
            "DefaultTestPlan.xctestplan",
            "OtherTestPlan.xctestplan",
            "YetAnotherTestPlan.xctestplan",
            "NonExistentTestPlan.xctestplan",
        ]),
    runAction: .runAction(executable: .project(path: "App", target: "App")),
    archiveAction: .archiveAction(configuration: "Debug", customArchiveName: "Something2")
)

let customFrameworkScheme = Scheme(
    name: "Workspace-Framework",
    shared: true,
    buildAction: .buildAction(
        targets: [.project(path: "Frameworks/Framework1", target: "Framework1")],
        preActions: []
    ),
    testAction: TestAction
        .targets([TestableTarget(target: .project(
            path: "Frameworks/Framework1",
            target: "Framework1Tests"
        ))]),
    archiveAction: .archiveAction(configuration: "Debug", customArchiveName: "Something2")
)

let workspace = Workspace(
    name: "Workspace",
    projects: [
        "App",
        "Frameworks/**",
    ],
    schemes: [
        customAppScheme,
        customAppSchemeWithTestPlans,
        customFrameworkScheme,
    ]
)
