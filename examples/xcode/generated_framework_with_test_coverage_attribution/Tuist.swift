import ProjectDescription

let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(attributeToTests: true)),
    project: .tuist()
)
