import ArgumentParser
import Foundation
import Testing
import TuistServer

@testable import TuistTestCommand

struct OnceTestReportTests {
    @Test func combines_batches_without_changing_case_identity_or_retries() throws {
        let plan = try plan()
        let report = try OnceTestReport.read(data(execution()), plan: plan, assigned: ["a", "b"], processSucceeded: true)
        #expect(report.success)
        #expect(report.modules.count == 1)
        let module = try #require(report.modules.first)
        #expect(module["name"] as? String == "libs/widget/tests")
        #expect(module["duration"] as? Int == 16)
        let cases = try #require(module["test_cases"] as? [[String: Any]])
        #expect(cases.count == 2)
        #expect(cases[0]["name"] as? String == "retries")
        #expect(cases[0]["test_suite_name"] as? String == "WidgetSuite")
        #expect(cases[0]["status"] as? String == "success")
        let attempts = try #require(cases[0]["repetitions"] as? [[String: Any]])
        #expect(attempts.map { $0["status"] as? String } == ["failure", "success"])
        #expect(attempts.map { $0["duration"] as? Int } == [13, 3])
        #expect(cases[1]["status"] as? String == "skipped")
        #expect(cases[1]["duration"] as? Int == 0)

        // Exercise the actual REST schema, including the nested repetitions and failure shape.
        let payload: [String: Any] = [
            "build_system": "once",
            "is_ci": true,
            "duration": 123,
            "status": "success",
            "test_modules": report.modules,
        ]
        let decoded = try JSONDecoder().decode(Operations.createTest.Input.Body.jsonPayload.self, from: data(payload))
        #expect(decoded.test_modules.first?.test_cases?.first?.repetitions?.count == 2)
    }

    @Test(arguments: [
        "incomplete",
        "other_plan",
        "missing_batch",
        "duplicate_batch",
        "other_target",
        "extra_case",
        "wrong_selection",
    ])
    func refuses_incomplete_or_different_scope(mutation: String) throws {
        var value = execution()
        var runs = try #require((value["execution"] as? [String: Any])?["runs"] as? [[String: Any]])
        switch mutation {
        case "incomplete": value["complete"] = false
        case "other_plan": value["plan_id"] = "different"
        case "missing_batch": runs.removeLast()
        case "duplicate_batch": runs[1] = runs[0]
        case "other_target": runs[0]["target"] = "libs/other/tests"
        case "wrong_selection": value["selected_batch_ids"] = ["a", "c"]
        default:
            var results = try #require(runs[0]["results"] as? [String: Any])
            var cases = try #require(results["cases"] as? [[String: Any]])
            cases.append([
                "id": "extra",
                "name": "extra",
                "suite": "WidgetSuite",
                "status": "passed",
                "attempts": [["status": "passed"]],
            ])
            results["cases"] = cases
            runs[0]["results"] = results
        }
        value["execution"] = ["runs": runs]
        let plan = try plan()
        #expect(throws: (any Error).self) {
            try OnceTestReport.read(data(value), plan: plan, assigned: ["a", "b"], processSucceeded: true)
        }
    }

    @Test func preserves_test_failures_and_process_failures() throws {
        let plan = try plan()
        let processFailure = try OnceTestReport.read(data(execution()), plan: plan, assigned: ["a", "b"], processSucceeded: false)
        #expect(!processFailure.success)
        #expect(processFailure.modules.count == 1)

        var value = execution()
        var runs = try #require((value["execution"] as? [String: Any])?["runs"] as? [[String: Any]])
        runs[1]["success"] = false
        runs[1]["exit_code"] = 1
        runs[1]["results"] = NSNull()
        runs[1]["results_error"] = "runner crashed"
        value["execution"] = ["runs": runs]
        value["success"] = false
        let report = try OnceTestReport.read(data(value), plan: plan, assigned: ["a", "b"], processSucceeded: false)
        #expect(!report.success)
        #expect((report.modules.first?["test_cases"] as? [[String: Any]])?.count == 1)
    }

    @Test func whole_target_fallback_is_not_an_empty_selection() throws {
        let plan = try plan(filters: [])
        var value = execution()
        let runs = try #require((value["execution"] as? [String: Any])?["runs"] as? [[String: Any]])
        value["execution"] = ["runs": [runs[0]]]
        value["selected_batch_ids"] = ["a"]
        let report = try OnceTestReport.read(data(value), plan: plan, assigned: ["a"], processSucceeded: true)
        #expect(report.success)
        #expect((report.modules.first?["test_cases"] as? [[String: Any]])?.count == 1)
    }

    @Test func validates_plan_command_options() throws {
        #expect(throws: (any Error).self) { try OnceTestPlanCommand.parse(["--shard-total", "0"]) }
        #expect(throws: (any Error).self) {
            try OnceTestPlanCommand.parse(["--shard-total", "2", "--target", "tests", "--changed-path", "src/a"])
        }
        let command = try OnceTestPlanCommand.parse(["--shard-total", "3", "--changed-path", "src/a", "--changed-path", "src/b"])
        #expect(command.changedPath == ["src/a", "src/b"])
    }

    private func plan(filters: [String] = ["retry"]) throws -> OnceTestPlan {
        try OnceTestPlan.read(data([
            "schema": "once.portable_test_plan.v1", "id": "portable",
            "plan": ["schema": "once.test_plan.v1", "batches": [
                ["id": "a", "target": "libs/widget/tests", "test_filters": filters],
                ["id": "b", "target": "libs/widget/tests", "test_filters": ["skip"]],
            ]],
        ]))
    }

    private func execution() -> [String: Any] {
        [
            "schema": "once.portable_test_execution.v1",
            "plan_id": "portable",
            "selected_batch_ids": ["b", "a"],
            "complete": true,
            "success": true,
            "execution": ["runs": [
                [
                    "batch_id": "a",
                    "target": "libs/widget/tests",
                    "exit_code": 0,
                    "success": true,
                    "results": ["schema": "once.test_results.v1", "target": "libs/widget/tests", "cases": [
                        ["id": "retry", "name": "retries", "suite": "WidgetSuite", "status": "flaky", "attempts": [
                            ["status": "failed", "duration_ms": 13.25, "failure": ["message": "first attempt"]],
                            ["status": "passed", "duration_ms": 2.7],
                        ]],
                    ]],
                ],
                [
                    "batch_id": "b",
                    "target": "libs/widget/tests",
                    "exit_code": 0,
                    "success": true,
                    "results": ["schema": "once.test_results.v1", "target": "libs/widget/tests", "cases": [
                        [
                            "id": "skip",
                            "name": "skips",
                            "suite": "OtherSuite",
                            "status": "skipped",
                            "attempts": [["status": "skipped"]],
                        ],
                    ]],
                ],
            ]],
        ]
    }

    private func data(_ value: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
}
