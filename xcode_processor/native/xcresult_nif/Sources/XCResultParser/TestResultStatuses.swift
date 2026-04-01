public struct TestResultStatuses: Sendable {
    public struct TestCaseStatus: Sendable {
        public let name: String
        public let testSuite: String?
        public let module: String?
        public let status: TestStatus

        public init(
            name: String,
            testSuite: String?,
            module: String?,
            status: TestStatus
        ) {
            self.name = name
            self.testSuite = testSuite
            self.module = module
            self.status = status
        }
    }

    public let testCases: [TestCaseStatus]

    public init(testCases: [TestCaseStatus]) {
        self.testCases = testCases
    }

    public var testCasesByModule: [String?: [TestCaseStatus]] {
        Dictionary(grouping: testCases) { $0.module }
    }

    public var hasFailures: Bool {
        testCases.contains { $0.status == .failed }
    }

    public func passingModuleNames() -> Set<String> {
        Set(
            testCasesByModule.compactMap { module, cases -> String? in
                guard let module else { return nil }
                return cases.allSatisfy({ $0.status != .failed }) ? module : nil
            }
        )
    }
}
