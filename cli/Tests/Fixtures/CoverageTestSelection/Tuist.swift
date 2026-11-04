import ProjectDescription

// The acceptance tests rewrite this with the project's handle and server.
let tuist = Tuist(
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
