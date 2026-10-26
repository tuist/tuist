import Foundation

struct OnceTestError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct OnceTestPlan: Decodable {
    struct Plan: Decodable {
        struct Batch: Decodable {
            let id: String
            let target: String
            let testFilters: [String]
        }

        let schema: String
        let batches: [Batch]
    }

    let schema: String
    let id: String
    let plan: Plan

    static func read(_ data: Data) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try decoder.decode(Self.self, from: data)
        guard value.schema == "once.portable_test_plan.v1", value.plan.schema == "once.test_plan.v1",
              !value.id.isEmpty, Set(value.plan.batches.map(\.id)).count == value.plan.batches.count,
              value.plan.batches.allSatisfy({ !$0.id.isEmpty && !$0.target.isEmpty })
        else {
            throw OnceTestError(message: "Once did not return a supported portable test plan. Upgrade Once and plan again.")
        }
        return value
    }
}

struct OnceTestReport {
    private struct Execution: Decodable {
        struct Body: Decodable {
            struct Run: Decodable {
                let batchId: String
                let target: String
                let exitCode: Int
                let success: Bool
                let results: Results?
                let resultsError: String?
            }

            let runs: [Run]
        }

        let schema: String
        let planId: String
        let selectedBatchIds: [String]
        let complete: Bool
        let success: Bool
        let execution: Body
    }

    private struct Results: Decodable {
        struct Case: Decodable {
            struct Attempt: Decodable {
                struct Failure: Decodable {
                    let message: String?
                }

                let status: String
                let durationMs: Double?
                let failure: Failure?
            }

            let id: String
            let name: String
            let suite: String
            let status: String
            let attempts: [Attempt]
        }

        let schema: String
        let target: String
        let cases: [Case]
    }

    let modules: [[String: Any]]
    let success: Bool

    static func read(_ data: Data, plan: OnceTestPlan, assigned: [String], processSucceeded: Bool) throws -> Self {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let value = try decoder.decode(Execution.self, from: data)
        let selected = Set(assigned)
        let batches = Dictionary(uniqueKeysWithValues: plan.plan.batches.filter { selected.contains($0.id) }.map { ($0.id, $0) })
        guard value.schema == "once.portable_test_execution.v1", value.planId == plan.id,
              selected.count == assigned.count, batches.count == assigned.count,
              value.selectedBatchIds.count == assigned.count, Set(value.selectedBatchIds) == selected,
              value.complete, value.execution.runs.count == assigned.count,
              Set(value.execution.runs.map(\.batchId)) == selected
        else {
            throw OnceTestError(
                message: "Once did not complete exactly the assigned batches. No successful shard will be reported."
            )
        }

        var byTarget: [String: [Results.Case]] = [:]
        var observed: [String: Set<String>] = [:]
        var success = processSucceeded && value.success
        for run in value.execution.runs {
            guard let batch = batches[run.batchId], batch.target == run.target else {
                throw OnceTestError(message: "Once returned results for a different target than assigned.")
            }
            success = success && run.success && run.exitCode == 0
            guard let results = run.results else {
                if !batch.testFilters.isEmpty || run.resultsError != nil { success = false }
                continue
            }
            guard results.schema == "once.test_results.v1", results.target == batch.target,
                  Set(results.cases.map(\.id)).count == results.cases.count,
                  batch.testFilters.isEmpty || Set(results.cases.map(\.id)) == Set(batch.testFilters)
            else {
                throw OnceTestError(message: "Once test results do not match the assigned batch scope.")
            }
            for test in results.cases {
                guard !test.id.isEmpty, !test.name.isEmpty, !test.suite.isEmpty, !test.attempts.isEmpty,
                      observed[batch.target, default: []].insert(test.id).inserted
                else {
                    throw OnceTestError(message: "Once returned duplicate or invalid test cases across batches.")
                }
                byTarget[batch.target, default: []].append(test)
                success = success && ["passed", "flaky", "skipped", "pending", "todo", "disabled"].contains(test.status)
            }
        }
        let modules: [[String: Any]] = byTarget.keys.sorted().map { target in
            let cases: [[String: Any]] = byTarget[target, default: []].sorted { $0.id < $1.id }.map { test in
                let repetitions: [[String: Any]] = test.attempts.enumerated().map { index, attempt in
                    [
                        "name": "Attempt \(index + 1)",
                        "repetition_number": index + 1,
                        "status": status(attempt.status),
                        "duration": milliseconds(attempt.durationMs),
                    ]
                }
                let failures: [[String: Any]] = test.attempts.compactMap(\.failure?.message).map {
                    ["message": $0, "line_number": 0]
                }
                return [
                    "name": test.name,
                    "test_suite_name": test.suite,
                    "status": status(test.status == "flaky" ? test.attempts.last!.status : test.status),
                    "duration": min(test.attempts.reduce(0) { $0 + milliseconds($1.durationMs) }, Int(Int32.max)),
                    "repetitions": repetitions,
                    "failures": failures,
                ]
            }
            let bySuite = Dictionary(grouping: cases, by: { $0["test_suite_name"] as? String ?? "" })
            let suites = bySuite.keys.sorted().map { suite in
                let members = bySuite[suite, default: []]
                return ["name": suite, "status": aggregateStatus(members), "duration": duration(members)] as [String: Any]
            }
            return [
                "name": target,
                "status": aggregateStatus(cases),
                "duration": duration(cases),
                "test_cases": cases,
                "test_suites": suites,
            ]
        }
        success = success && !modules.contains { $0["status"] as? String == "failure" }
        return Self(modules: modules, success: success)
    }

    private static func status(_ status: String) -> String {
        switch status {
        case "passed": "success"
        case "failed", "errored", "timed_out": "failure"
        default: "skipped"
        }
    }

    private static func aggregateStatus(_ cases: [[String: Any]]) -> String {
        if cases.contains(where: { $0["status"] as? String == "failure" }) { return "failure" }
        if cases.allSatisfy({ $0["status"] as? String == "skipped" }) { return "skipped" }
        return "success"
    }

    private static func milliseconds(_ value: Double?) -> Int {
        guard let value, value.isFinite, value > 0 else { return 0 }
        return Int(min(value.rounded(), Double(Int32.max)))
    }

    private static func duration(_ cases: [[String: Any]]) -> Int {
        min(cases.reduce(0) { $0 + ($1["duration"] as? Int ?? 0) }, Int(Int32.max))
    }
}
