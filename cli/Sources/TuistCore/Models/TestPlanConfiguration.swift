public struct TestPlanConfiguration {
    public let testPlan: String
    public let configurations: [String]
    public let skipConfigurations: [String]

    public init(
        testPlan: String,
        configurations: [String] = [],
        skipConfigurations: [String] = []
    ) {
        self.testPlan = testPlan
        self.configurations = configurations
        self.skipConfigurations = skipConfigurations
    }
}
