#if MOCKING
    extension Components.Schemas.TestCase {
        public static func test(
            avgDuration: Int = 100,
            id: String = "test-case-id",
            isFlaky: Bool = false,
            isQuarantined: Bool = false,
            module: Components.Schemas.TestCase.modulePayload = .test(),
            name: String = "testExample",
            suite: Components.Schemas.TestCase.suitePayload? = nil,
            url: String = "https://tuist.dev/test-case"
        ) -> Self {
            .init(
                avg_duration: avgDuration,
                id: id,
                is_flaky: isFlaky,
                is_quarantined: isQuarantined,
                module: module,
                name: name,
                suite: suite,
                url: url
            )
        }
    }

    extension Components.Schemas.TestCase.modulePayload {
        public static func test(
            id: String = "module-id",
            name: String = "TestModule"
        ) -> Self {
            .init(id: id, name: name)
        }
    }

    extension Components.Schemas.TestCase.suitePayload {
        public static func test(
            id: String = "suite-id",
            name: String = "TestSuite"
        ) -> Self {
            .init(id: id, name: name)
        }
    }
#endif
