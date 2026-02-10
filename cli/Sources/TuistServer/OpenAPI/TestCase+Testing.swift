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

#if DEBUG
    extension Operations.getTestCase.Output.Ok.Body.jsonPayload {
        public static func test(
            avgDuration: Int = 100,
            failedRuns: Int = 2,
            flakinessRate: Double = 5.0,
            id: String = "test-case-id",
            isFlaky: Bool = false,
            isQuarantined: Bool = false,
            lastDuration: Int = 150,
            lastRanAt: Int = 1_700_000_000,
            lastStatus: Operations.getTestCase.Output.Ok.Body.jsonPayload.last_statusPayload = .success,
            module: Operations.getTestCase.Output.Ok.Body.jsonPayload.modulePayload = .test(),
            name: String = "testExample",
            reliabilityRate: Double? = 95.0,
            suite: Operations.getTestCase.Output.Ok.Body.jsonPayload.suitePayload? = nil,
            totalRuns: Int = 50,
            url: String = "https://tuist.dev/test-case"
        ) -> Self {
            .init(
                avg_duration: avgDuration,
                failed_runs: failedRuns,
                flakiness_rate: flakinessRate,
                id: id,
                is_flaky: isFlaky,
                is_quarantined: isQuarantined,
                last_duration: lastDuration,
                last_ran_at: lastRanAt,
                last_status: lastStatus,
                module: module,
                name: name,
                reliability_rate: reliabilityRate,
                suite: suite,
                total_runs: totalRuns,
                url: url
            )
        }
    }

    extension Operations.getTestCase.Output.Ok.Body.jsonPayload.modulePayload {
        public static func test(
            id: String = "module-id",
            name: String = "TestModule"
        ) -> Self {
            .init(id: id, name: name)
        }
    }

    extension Operations.getTestCase.Output.Ok.Body.jsonPayload.suitePayload {
        public static func test(
            id: String = "suite-id",
            name: String = "TestSuite"
        ) -> Self {
            .init(id: id, name: name)
        }
    }

    extension Operations.getTestCaseRun.Output.Ok.Body.jsonPayload {
        public static func test(
            duration: Int = 1500,
            failures: [Operations.getTestCaseRun.Output.Ok.Body.jsonPayload.failuresPayloadPayload] = [],
            gitBranch: String? = "main",
            gitCommitSha: String? = "abc1234",
            id: String = "run-id",
            isCi: Bool = true,
            isFlaky: Bool = false,
            isNew: Bool = false,
            moduleName: String = "AppTests",
            name: String = "testExample",
            ranAt: Int? = 1_700_000_000,
            repetitions: [Operations.getTestCaseRun.Output.Ok.Body.jsonPayload.repetitionsPayloadPayload] = [],
            scheme: String? = "App",
            status: Operations.getTestCaseRun.Output.Ok.Body.jsonPayload.statusPayload = .success,
            suiteName: String? = "ExampleTests",
            testCaseId: String? = "test-case-id"
        ) -> Self {
            .init(
                duration: duration,
                failures: failures,
                git_branch: gitBranch,
                git_commit_sha: gitCommitSha,
                id: id,
                is_ci: isCi,
                is_flaky: isFlaky,
                is_new: isNew,
                module_name: moduleName,
                name: name,
                ran_at: ranAt,
                repetitions: repetitions,
                scheme: scheme,
                status: status,
                suite_name: suiteName,
                test_case_id: testCaseId
            )
        }
    }

    extension Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload {
        public static func test(
            currentPage: Int = 1,
            pageSize: Int = 10,
            totalPages: Int = 1,
            hasNextPage: Bool = false,
            hasPreviousPage: Bool = false,
            testCaseRuns: [Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test_case_runsPayloadPayload]
        ) -> Self {
            .init(
                pagination_metadata: .init(
                    current_page: currentPage,
                    has_next_page: hasNextPage,
                    has_previous_page: hasPreviousPage,
                    page_size: pageSize,
                    total_count: testCaseRuns.count,
                    total_pages: totalPages
                ),
                test_case_runs: testCaseRuns
            )
        }
    }

    extension Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test_case_runsPayloadPayload {
        public static func test(
            duration: Int = 1500,
            gitBranch: String? = "main",
            gitCommitSha: String? = "abc1234def5678",
            id: String = "run-id",
            isCi: Bool = true,
            isFlaky: Bool = false,
            isNew: Bool = false,
            ranAt: Int? = 1_700_000_000,
            scheme: String? = "App",
            status: Operations.listTestCaseRuns.Output.Ok.Body.jsonPayload.test_case_runsPayloadPayload
                .statusPayload = .success
        ) -> Self {
            .init(
                duration: duration,
                git_branch: gitBranch,
                git_commit_sha: gitCommitSha,
                id: id,
                is_ci: isCi,
                is_flaky: isFlaky,
                is_new: isNew,
                ran_at: ranAt,
                scheme: scheme,
                status: status
            )
        }
    }
#endif
