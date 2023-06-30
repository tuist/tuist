public struct TestPlanConfiguration {
    public let testPlan: String
    public let testConfigurations: [String]
    public let skipTestConfigurations: [String]

    public init(
        testPlan: String,
        testConfigurations: [String] = [],
        skipTestConfigurations: [String] = []
    ) {
        self.testPlan = testPlan
        self.testConfigurations = testConfigurations
        self.skipTestConfigurations = skipTestConfigurations
    }
}
