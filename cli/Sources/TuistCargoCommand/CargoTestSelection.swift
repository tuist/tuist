import Foundation
import TuistAlert
import TuistCI
import TuistProcess
import TuistServer

struct CargoTestSelectionError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct CargoTestQuarantine {
    struct Test {
        let module: String
        let suite: String?
        let name: String

        func matches(module: String, suite: String, name: String) -> Bool {
            self.module == module && (self.suite ?? "") == suite && self.name == name
        }
    }

    var muted: [Test] = []
    var skipped: [Test] = []

    static func fetch(_ context: CargoExecutionContext, service: ListTestCasesServicing = ListTestCasesService()) async -> Self {
        guard context.environment["TUIST_TEST_SKIP_QUARANTINE"] != "1",
              context.environment["TUIST_TEST_SKIP_QUARANTINE"] != "true"
        else {
            return Self()
        }
        do {
            var result = Self()
            for state in [Operations.listTestCases.Input.Query.statePayload.muted, .skipped] {
                var page = 1
                while true {
                    let response = try await service.listTestCases(
                        fullHandle: context.reporting.handle, serverURL: context.reporting.serverURL,
                        flaky: nil, quarantined: nil, state: state, page: page, pageSize: 500
                    )
                    let tests = response.test_cases.map { Test(module: $0.module.name, suite: $0.suite?.name, name: $0.name) }
                    if state == .muted {
                        result.muted += tests
                    } else {
                        result.skipped += tests
                    }
                    guard response.pagination_metadata.has_next_page else {
                        break
                    }
                    page += 1
                }
            }
            return result
        } catch {
            let message = "Failed to fetch Cargo quarantine: \(error.localizedDescription). Running without quarantine."
            AlertController.current.warning(.alert("\(message)"))
            // Cargo bypasses generic completion rendering and reserves stdout for Cargo's output.
            FileHandle.standardError.write(Data("warning: \(message)\n".utf8))
            return Self()
        }
    }

    func matches(_ tests: [Test], module: String, name: String, doctest: Bool) -> Bool {
        let identity = doctest ? (suite: "doctests", name: name) : NextestReport.identity(name)
        return tests.contains { $0.matches(module: module, suite: identity.suite, name: identity.name) }
    }

    func mark(_ report: CargoTestReport) -> CargoTestReport {
        let modules = report.modules.map { original in
            var module = original
            let name = module["name"] as? String ?? ""
            let cases = (module["test_cases"] as? [[String: Any]] ?? []).map { original in
                var test = original
                test["is_quarantined"] = (muted + skipped).contains {
                    $0.matches(module: name, suite: test["test_suite_name"] as? String ?? "", name: test["name"] as? String ?? "")
                }
                return test
            }
            module["test_cases"] = cases
            module["status"] = cases.contains { $0["status"] as? String == "failure" && $0["is_quarantined"] as? Bool != true }
                ? "failure" : "success"
            module["test_suites"] = (module["test_suites"] as? [[String: Any]] ?? []).map { original in
                var suite = original
                suite["status"] = cases.contains {
                    $0["test_suite_name"] as? String == suite["name"] as? String
                        && $0["status"] as? String == "failure" && $0["is_quarantined"] as? Bool != true
                } ? "failure" : "success"
                return suite
            }
            return module
        }
        return CargoTestReport(modules: modules, duration: report.duration)
    }

    func permitsFailure(_ error: Error, result: CargoTestResult?) -> Bool {
        guard case CommandError.terminated(101, _, _) = error,
              result?.ordinaryTestFailure == true, let report = result?.report
        else {
            return false
        }
        let failures = report.modules.flatMap { $0["test_cases"] as? [[String: Any]] ?? [] }
            .filter { $0["status"] as? String == "failure" }
        return !failures.isEmpty && failures.allSatisfy { $0["is_quarantined"] as? Bool == true }
    }
}

/// Cargo owns compilation, target runners, runtime environments and doctest execution.
/// Only its package/target selection is changed; compiled products are never launched directly.
struct CargoTestSelection {
    struct Module {
        let name: String
        let arguments: [String]
        let doctest: Bool
    }

    let runner: CommandRunning

    static func planning(_ arguments: [String]) throws -> (arguments: [String], options: [String: Int]) {
        var forwarded: [String] = []
        var options: [String: Int] = [:]
        var index = 0
        let names: Set<String> = ["--shard-min", "--shard-max", "--shard-total", "--shard-max-duration"]
        while index < arguments.count {
            if arguments[index] == "--" {
                forwarded += arguments[index...]; break
            }
            let parts = arguments[index].split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let key = parts[0]
            if names.contains(key) {
                let inline = parts.count == 2
                guard inline || index + 1 < arguments.count,
                      let value = Int(inline ? parts[1] : arguments[index + 1], radix: 10), value > 0,
                      options[key] == nil
                else {
                    throw CargoTestSelectionError(message: "\(key) requires one positive integer.")
                }
                options[key] = value
                index += inline ? 1 : 2
            } else {
                forwarded.append(arguments[index])
                index += 1
            }
        }
        guard options.isEmpty || forwarded.prefix(while: { $0 != "--" }).contains("--no-run") else {
            throw CargoTestSelectionError(message: "Shard counts require 'tuist cargo test --no-run'.")
        }
        guard options["--shard-total"] == nil || (options["--shard-min"] == nil && options["--shard-max"] == nil),
              (options["--shard-min"] ?? 1) <= (options["--shard-max"] ?? Int.max)
        else {
            throw CargoTestSelectionError(message: "Use --shard-total or a valid --shard-min/--shard-max range.")
        }
        return (forwarded, options)
    }

    func inventory(
        _ context: CargoExecutionContext, requiresSinglePackage: Bool = true
    ) async throws -> (modules: [Module], buildFinished: Date?) {
        guard !CargoInvocation(context.arguments).changesDirectory else {
            throw CargoTestSelectionError(
                message: "Change into the workspace before sharding or quarantining Cargo tests; -C is unsupported."
            )
        }
        let separator = context.arguments.firstIndex(of: "--") ?? context.arguments.endIndex
        let arguments = context.arguments[..<separator].filter { $0 != "--no-run" } + context.arguments[separator...]
        guard CargoTestService.observes(CargoInvocation(arguments), environment: context.environment) else {
            throw CargoTestSelectionError(
                message: "Cargo test selection requires standard captured libtest output, without --list, quiet, verbose or alternate formats."
            )
        }
        let targets = try await CargoTestTargets.read(context, arguments: arguments, requiresSinglePackage: requiresSinglePackage)
        let output = CargoTestOutput(printsStdout: false)
        try await runner.runWithOutputHandler(
            arguments: ["/usr/bin/env", context.executable] + Self.listArguments(arguments),
            environment: context.environment, workingDirectory: context.directory,
            onIncompleteOutput: { output.discard() }, onOutput: { output.receive($0) }
        )
        let captured = output.state.withLock { $0 }
        guard captured.bounded, let errors = String(data: captured.stderr, encoding: .utf8) else {
            throw CargoTestSelectionError(message: "Cargo test enumeration is incomplete, oversized or not UTF-8.")
        }
        var modules: [Module] = []
        for line in errors.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
            .components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) })
        {
            guard line.hasPrefix("Running ") || line.hasPrefix("Doc-tests ") else {
                continue
            }
            guard let heading = CargoTestReport.heading(line, targets: targets, directory: context.directory.pathString),
                  let target = targets.first(where: {
                      heading.module == $0.module || (heading.isDoctest && heading.module == "\($0.module)::doctest/\($0.name)")
                  })
            else {
                throw CargoTestSelectionError(message: "Cargo test target attribution is ambiguous: \(line)")
            }
            let selector: [String]
            if heading.isDoctest {
                selector = ["--doc"]
            } else if target.isLibrary {
                selector = ["--lib"]
            } else if let kind = [
                "bin",
                "example",
                "bench",
            ].first(where: { target.module.contains("::\($0)/") }) {
                selector = ["--\(kind)", target.name]
            } else {
                selector = ["--test", target.name]
            }
            let package = String(target.module.components(separatedBy: "::")[0])
            let scoped = try Self.scopedArguments(arguments, selector: ["--package", package] + selector)
            modules.append(Module(name: heading.module, arguments: scoped, doctest: heading.isDoctest))
        }
        guard Set(modules.map(\.name)).count == modules.count else {
            throw CargoTestSelectionError(message: "Cargo test enumeration contains duplicate module identities.")
        }
        guard !modules.isEmpty || captured.stdout.isEmpty else {
            throw CargoTestSelectionError(
                message: "Cargo did not identify the listed test targets. Disable configured quiet output before sharding or quarantining tests."
            )
        }
        return (modules, captured.build.finished)
    }

    private static func listArguments(_ arguments: [String]) -> [String] {
        arguments + (arguments.contains("--") ? [] : ["--"]) + ["--list"]
    }

    static func scopedArguments(_ arguments: [String], selector: [String]) throws -> [String] {
        guard let command = CargoInvocation(arguments).commandIndex else {
            throw CargoTestSelectionError(message: "Missing Cargo test command.")
        }
        let values: Set<String> = ["--package", "-p", "--exclude", "--test", "--bin", "--example", "--bench"]
        let flags: Set<String> = [
            "--workspace",
            "--all",
            "--lib",
            "--tests",
            "--bins",
            "--examples",
            "--benches",
            "--all-targets",
            "--doc",
            "--no-run",
        ]
        let retainedValues: Set<String> = [
            "--features",
            "-F",
            "--target",
            "--target-dir",
            "--profile",
            "--jobs",
            "-j",
            "--manifest-path",
            "--config",
            "--color",
            "--lockfile-path",
        ]
        let retainedFlags: Set<String> = [
            "--all-features",
            "--no-default-features",
            "--release",
            "-r",
            "--locked",
            "--offline",
            "--frozen",
            "--no-fail-fast",
            "--keep-going",
            "--future-incompat-report",
        ]
        var result = Array(arguments[...command]) + selector
        var index = command + 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                result += arguments[index...]; break
            }
            let key = argument.components(separatedBy: "=")[0]
            if values.contains(key) {
                index += argument.contains("=") ? 1 : 2; continue
            }
            if flags.contains(argument) {
                index += 1; continue
            }
            if argument.hasPrefix("-p"), argument.count > 2 {
                index += 1; continue
            }
            if retainedValues.contains(key) {
                result.append(argument)
                if !argument.contains("=") {
                    guard index + 1 < arguments.count
                    else {
                        throw CargoTestSelectionError(message: "Missing value for \(argument).")
                    }
                    result.append(arguments[index + 1]); index += 1
                }
            } else if !argument.hasPrefix("-") || retainedFlags.contains(argument)
                || ["-F", "-j"].contains(where: { argument.hasPrefix($0) && argument.count > 2 })
            {
                result.append(argument)
            } else {
                throw CargoTestSelectionError(message: "Cargo test selection does not support \(argument).")
            }
            index += 1
        }
        return result
    }

    func plan(_ context: CargoExecutionContext, options: [String: Int]) async throws {
        guard let reference = context.environment["TUIST_SHARD_REFERENCE"] ?? CIController().ciInfo()?.shardReference else {
            throw CargoTestSelectionError(message: "Set TUIST_SHARD_REFERENCE to identify the shard plan.")
        }
        let modules = try await inventory(context).modules
        guard !modules.isEmpty else {
            throw CargoTestSelectionError(message: "No Cargo test modules were found.")
        }
        let plan = try await CreateShardPlanService().createShardPlan(
            fullHandle: context.reporting.handle, serverURL: context.reporting.serverURL, reference: reference,
            modules: modules.map(\.name), parallelizableModules: nil, testSuites: nil, skippedTestSuites: nil,
            shardMin: options["--shard-min"], shardMax: options["--shard-max"], shardTotal: options["--shard-total"],
            shardMaxDuration: options["--shard-max-duration"], shardGranularity: .module, buildRunId: nil, gitBranch: nil
        )
        try CargoShardService.emit(plan, environment: context.environment)
    }

    func execute(
        _ context: CargoExecutionContext,
        quarantine: CargoTestQuarantine,
        completed: (CargoTestResult) -> Void
    ) async throws {
        if context.environment["TUIST_SHARD_INDEX"] == nil, quarantine.skipped.isEmpty {
            _ = try await inventory(context, requiresSinglePackage: false)
            let separator = context.arguments.firstIndex(of: "--") ?? context.arguments.endIndex
            let cargoArguments = Array(context.arguments[..<separator])
            let selected = CargoExecutionContext(
                executable: context.executable, directory: context.directory,
                arguments: cargoArguments + (cargoArguments.contains("--no-fail-fast") ? [] : ["--no-fail-fast"])
                    + context.arguments[separator...],
                environment: context.environment, reporting: context.reporting
            )
            var result: CargoTestResult?
            do {
                try await CargoTestService(runner: runner).execute(selected) {
                    var marked = $0
                    marked.report = marked.report.map { quarantine.mark($0) }
                    result = marked
                    completed(marked)
                }
            } catch {
                if !quarantine.permitsFailure(error, result: result) { throw error }
            }
            return
        }
        let inventory = try await inventory(context)
        var modules = inventory.modules
        let buildFinished = inventory.buildFinished
        var shardID: String?
        var shardIndex: Int?
        if let value = context.environment["TUIST_SHARD_INDEX"] {
            guard let index = Int(value, radix: 10), index >= 0,
                  let reference = context.environment["TUIST_SHARD_REFERENCE"] ?? CIController().ciInfo()?.shardReference
                  ?? context.environment["TUIST_SHARD_PLAN_ID"]
            else {
                throw CargoTestSelectionError(message: "Set a non-negative TUIST_SHARD_INDEX and a shard reference or plan ID.")
            }
            let shard = try await GetShardService().getShard(
                fullHandle: context.reporting.handle, serverURL: context.reporting.serverURL, reference: reference,
                shardPlanId: context.environment["TUIST_SHARD_PLAN_ID"], shardIndex: index
            )
            guard shard.suites.additionalProperties.isEmpty, (shard.skip ?? []).isEmpty,
                  Set(shard.modules).isSubset(of: Set(modules.map(\.name)))
            else {
                throw CargoTestSelectionError(
                    message: "Cargo requires a module-granularity plan matching this workspace and test selection."
                )
            }
            modules = modules.filter { shard.modules.contains($0.name) }
            shardID = shard.shard_plan_id
            shardIndex = index
        }
        var reports: [CargoTestReport] = []
        var error: Error?
        var complete = true
        for module in modules {
            try Task.checkCancellation()
            let excluded = quarantine.skipped.filter { $0.module == module.name }
            var arguments = module.arguments
            var skipped: [String] = []
            if !excluded.isEmpty {
                let listing = try await context.reporting.process.capture(
                    context.executable, arguments: Self.listArguments(arguments) + ["--format", "terse"],
                    environment: context.environment, directory: context.directory
                )
                let names = try Self.testNames(listing)
                if names.isEmpty {
                    continue
                }
                skipped = names.filter { quarantine.matches(excluded, module: module.name, name: $0, doctest: module.doctest) }
                arguments = try Self.excluding(skipped, from: names, arguments: arguments, doctest: module.doctest)
            }
            var result: CargoTestResult?
            do {
                if !arguments.isEmpty {
                    let selected = CargoExecutionContext(
                        executable: context.executable, directory: context.directory, arguments: arguments,
                        environment: context.environment, reporting: context.reporting
                    )
                    try await CargoTestService(runner: runner).execute(selected) { result = $0 }
                }
            } catch let failure {
                var marked = result
                let report = result?.report.map { quarantine.mark($0) }
                marked?.report = report
                if !quarantine.permitsFailure(failure, result: marked) {
                    error = error ?? failure
                }
            }
            if let report = result?.report {
                var marked = quarantine.mark(report)
                if !skipped.isEmpty {
                    marked = Self.addSkipped(skipped, module: module, to: marked)
                }
                reports.append(marked)
            } else if arguments.isEmpty {
                reports.append(Self.addSkipped(skipped, module: module, to: CargoTestReport(modules: [], duration: 0)))
            } else if result?.report == nil, error != nil {
                complete = false
            } else if result?.report == nil {
                // A target may contain no matching tests. Verify that independently before accepting an empty result.
                let listing = try await context.reporting.process.capture(
                    context.executable, arguments: Self.listArguments(arguments) + ["--format", "terse"],
                    environment: context.environment, directory: context.directory
                )
                if try !Self.testNames(listing).isEmpty {
                    complete = false
                }
            }
            if error != nil, !context.arguments.prefix(while: { $0 != "--" }).contains("--no-fail-fast") {
                break
            }
        }
        let report = complete ? CargoTestReport(
            modules: reports.flatMap(\.modules),
            duration: reports.reduce(0) { $0 + $1.duration }
        ) : nil
        completed(CargoTestResult(
            report: report, buildFinished: buildFinished, finished: Date(), canReportBuildFailure: false,
            shardID: shardID, shardIndex: shardIndex
        ))
        if let error {
            throw error
        }
    }
}

extension CargoTestSelection {
    static func testNames(_ listing: String) throws -> [String] {
        var names: [String] = []
        for line in listing.components(separatedBy: .newlines) where !line.isEmpty {
            guard line.hasSuffix(": test"), names.count < 100_000 else {
                throw CargoTestSelectionError(message: "Cargo returned a nonstandard or oversized libtest inventory.")
            }
            names.append(String(line.dropLast(6)))
        }
        guard Set(names).count == names.count
        else {
            throw CargoTestSelectionError(message: "Cargo returned duplicate test names.")
        }
        return names
    }

    static func excluding(_ skipped: [String], from names: [String], arguments: [String], doctest: Bool) throws -> [String] {
        guard !skipped.isEmpty else {
            return arguments
        }
        let retained = names.filter { !skipped.contains($0) }
        guard !retained.isEmpty else {
            return []
        }
        if !doctest {
            return try exactArguments(arguments, names: retained)
        }
        guard !arguments.drop(while: { $0 != "--" }).contains("--exact") else {
            throw CargoTestSelectionError(
                message: "Rustdoc cannot safely skip individual doctests with --exact. Remove --exact or set TUIST_TEST_SKIP_QUARANTINE=1."
            )
        }
        var filters: [String] = []
        for name in skipped {
            // rustdoc splits harness arguments on whitespace, even when Cargo received one quoted argument.
            // Use only substrings proven not to exclude a retained test in this particular module.
            let candidates = [name] + name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard let filter = candidates.first(where: { candidate in
                !candidate.contains(where: \.isWhitespace) && !retained.contains(where: { $0.contains(candidate) })
            }) else {
                throw CargoTestSelectionError(
                    message: "Rustdoc cannot safely skip '\(name)' without excluding another doctest. Set TUIST_TEST_SKIP_QUARANTINE=1 to run without quarantine."
                )
            }
            filters += ["--skip", filter]
        }
        return arguments + (arguments.contains("--") ? [] : ["--"]) + filters
    }

    private static func exactArguments(_ arguments: [String], names: [String]) throws -> [String] {
        guard let command = CargoInvocation(arguments).commandIndex else {
            throw CargoTestSelectionError(message: "Missing Cargo test command.")
        }
        let cargoValues: Set<String> = [
            "--package",
            "-p",
            "--exclude",
            "--test",
            "--bin",
            "--example",
            "--bench",
            "--features",
            "-F",
            "--target",
            "--target-dir",
            "--profile",
            "--jobs",
            "-j",
            "--manifest-path",
            "--config",
            "--color",
            "--lockfile-path",
        ]
        let harnessValues: Set<String> = ["--test-threads", "--skip", "--format", "--color", "--logfile", "--shuffle-seed"]
        let harnessFlags: Set<String> = ["--ignored", "--include-ignored", "--test", "--shuffle", "--exclude-should-panic"]
        var result = Array(arguments[...command])
        var harness: [String] = []
        var isHarness = false
        var index = command + 1
        while index < arguments.count {
            let argument = arguments[index]
            if argument == "--" {
                isHarness = true; index += 1; continue
            }
            let key = argument.components(separatedBy: "=")[0]
            let values = isHarness ? harnessValues : cargoValues
            var retained: [String] = []
            if values.contains(key) {
                retained.append(argument)
                if !argument.contains("=") {
                    guard index + 1 < arguments.count
                    else {
                        throw CargoTestSelectionError(message: "Missing value for \(argument).")
                    }
                    retained.append(arguments[index + 1]); index += 1
                }
            } else if argument.hasPrefix("-") {
                if isHarness {
                    if argument != "--exact" {
                        guard harnessFlags.contains(argument) else {
                            throw CargoTestSelectionError(
                                message: "Cargo skip quarantine does not support harness option \(argument)."
                            )
                        }
                        retained.append(argument)
                    }
                } else {
                    retained.append(argument)
                }
            }
            if isHarness {
                harness += retained
            } else {
                result += retained
            }
            index += 1
        }
        return result + ["--", "--exact"] + harness + names
    }

    private static func addSkipped(_ names: [String], module: Module, to report: CargoTestReport) -> CargoTestReport {
        var modules = report.modules
        let index = modules.firstIndex { $0["name"] as? String == module.name }
        var payload = index.map { modules[$0] } ?? [
            "name": module.name,
            "duration": 0,
            "status": "success",
            "test_suites": [[String: Any]](),
        ]
        let cases: [[String: Any]] = names.map { name in
            let identity = module.doctest ? (suite: "doctests", name: name) : NextestReport.identity(name)
            return [
                "name": identity.name,
                "test_suite_name": identity.suite,
                "duration": 0,
                "status": "skipped",
                "is_quarantined": true,
            ]
        }
        payload["test_cases"] = (payload["test_cases"] as? [[String: Any]] ?? []) + cases
        var suites = payload["test_suites"] as? [[String: Any]] ?? []
        for name in Set(cases.compactMap { $0["test_suite_name"] as? String }).sorted()
            where !suites.contains(where: { $0["name"] as? String == name })
        {
            suites.append(["name": name, "duration": 0, "status": "success"])
        }
        payload["test_suites"] = suites
        if let index {
            modules[index] = payload
        } else {
            modules.append(payload)
        }
        return CargoTestReport(modules: modules, duration: report.duration)
    }
}
