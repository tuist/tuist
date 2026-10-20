import Foundation

struct CargoTestTarget {
    let module: String
    let name: String
    let source: String
    let isLibrary: Bool
    let packageDirectory: String

    static func read(_ metadata: [String: Any], arguments: [String] = []) -> [Self] {
        let packages = metadata["packages"] as? [[String: Any]] ?? []
        let names = Set(packages.compactMap { $0["name"] as? String })
        let selection = selectedPackages(arguments)
        guard selection.allSatisfy(names.contains) else { return [] }
        let selectsWorkspace = arguments.prefix(while: { $0 != "--" }).contains { ["--workspace", "--all"].contains($0) }
        let selected = selection.isEmpty || selectsWorkspace ? names : Set(selection)
        return packages.flatMap { package -> [Self] in
            guard let packageName = package["name"] as? String, selected.contains(packageName),
                  let manifest = package["manifest_path"] as? String else { return [] }
            let packageDirectory = (manifest as NSString).deletingLastPathComponent
            return (package["targets"] as? [[String: Any]] ?? []).compactMap { target in
                guard let name = target["name"] as? String, let source = target["src_path"] as? String,
                      let kinds = target["kind"] as? [String], let kind = kinds.first else { return nil }
                let isLibrary = !Set(kinds).isDisjoint(with: ["lib", "rlib", "dylib", "cdylib", "staticlib", "proc-macro"])
                let identifier = isLibrary ? packageName : kind == "test" ? "\(packageName)::\(name)" : "\(packageName)::\(kind)/\(name)"
                return Self(
                    module: identifier,
                    name: name,
                    source: source,
                    isLibrary: isLibrary,
                    packageDirectory: packageDirectory
                )
            }
        }
    }

    private static func selectedPackages(_ arguments: [String]) -> [String] {
        let arguments = Array(arguments.prefix(while: { $0 != "--" }))
        var packages: [String] = []
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if ["--package", "-p"].contains(argument), index + 1 < arguments.count {
                packages.append(arguments[index + 1])
                index += 2
                continue
            }
            if argument.hasPrefix("--package=") {
                packages.append(String(argument.dropFirst("--package=".count)))
            } else if argument.hasPrefix("-p"), argument.count > 2 {
                packages.append(String(argument.dropFirst(2)))
            }
            index += 1
        }
        return packages
    }
}

struct CargoTestReport {
    struct Test {
        let name: String
        let status: String
    }

    struct Section {
        let tests: [Test]
        let duration: Int
        var doctestFooter = false
    }

    struct Heading {
        let module: String
        let isDoctest: Bool
    }

    let modules: [[String: Any]]
    let duration: Int

    static func read(stdout: Data, stderr: Data, targets: [CargoTestTarget], directory: String) -> Self? {
        guard stdout.count + stderr.count <= 50_000_000,
              let output = String(data: stdout, encoding: .utf8), let errors = String(data: stderr, encoding: .utf8)
        else { return nil }
        let lines = clean(output).components(separatedBy: .newlines)
        guard let sections = sections(lines), !sections.isEmpty else { return nil }
        var headings: [Heading] = []
        for line in clean(errors).components(separatedBy: .newlines) {
            let line = line.trimmingCharacters(in: .whitespaces)
            guard line.hasPrefix("Running ") || line.hasPrefix("Doc-tests ") else { continue }
            guard let heading = heading(line, targets: targets, directory: directory), headings.count < 1000 else { return nil }
            headings.append(heading)
        }
        guard let groups = assign(sections, to: headings) else { return nil }
        var modules: [[String: Any]] = []
        var duration = 0
        for (heading, group) in zip(headings, groups) {
            let tests = group.flatMap(\.tests)
            guard Set(tests.map(\.name)).count == tests.count,
                  !heading.isDoctest || tests.allSatisfy({ !($0.name as NSString).isAbsolutePath }) else { return nil }
            let elapsed = group.reduce(0) { $0 + $1.duration }
            guard elapsed <= Int(Int32.max), duration + elapsed <= Int(Int32.max) else { return nil }
            duration += elapsed
            let cases: [[String: Any]] = tests.map { test in
                let identity = heading.isDoctest ? (suite: "doctests", name: test.name) : NextestReport.identity(test.name)
                return ["name": identity.name, "test_suite_name": identity.suite, "status": test.status, "duration": 0]
            }
            let suites: [[String: Any]] = Dictionary(grouping: cases, by: { $0["test_suite_name"] as? String ?? "" })
                .sorted { $0.key < $1.key }.map { name, cases in
                    [
                        "name": name,
                        "duration": 0,
                        "status": cases.contains { $0["status"] as? String == "failure" } ? "failure" : "success",
                    ]
                }
            modules.append([
                "name": heading.module, "duration": elapsed,
                "status": tests.contains { $0.status == "failure" } ? "failure" : "success",
                "test_cases": cases, "test_suites": suites,
            ])
        }
        guard Set(headings.map(\.module)).count == headings.count,
              modules.contains(where: { !($0["test_cases"] as? [[String: Any]] ?? []).isEmpty }) else { return nil }
        return Self(modules: modules, duration: duration)
    }

    private static func clean(_ string: String) -> String {
        string.replacingOccurrences(of: "\u{1B}\\[[0-9;]*m", with: "", options: .regularExpression)
    }

    private static let runningPattern = try? NSRegularExpression(pattern: #"^running ([0-9]+) tests?$"#)
    private static let testPattern = try? NSRegularExpression(pattern: #"^test (.+) \.\.\. (ok|FAILED|ignored(?:, .*)?)$"#)
    private static let headingPattern = try? NSRegularExpression(pattern: #"^Running (?:unittests )?(.+) \((.+)\)$"#)
    private static let summaryPattern = try? NSRegularExpression(
        pattern: #"^test result: (ok|FAILED)\. ([0-9]+) passed; ([0-9]+) failed; ([0-9]+) ignored; 0 measured; [0-9]+ filtered out; finished in ([0-9]+(?:\.[0-9]+)?)s$"#
    )

    private static func captures(_ pattern: NSRegularExpression?, _ line: String) -> [String]? {
        guard let regex = pattern,
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else { return nil }
        return (1 ..< match.numberOfRanges).compactMap { Range(match.range(at: $0), in: line).map { String(line[$0]) } }
    }

    private static func heading(_ line: String, targets: [CargoTestTarget], directory _: String) -> Heading? {
        if line.hasPrefix("Doc-tests ") {
            let name = String(line.dropFirst("Doc-tests ".count))
            let matches = targets.filter { $0.isLibrary && $0.name.replacingOccurrences(of: "-", with: "_") == name }
            guard matches.count == 1, let target = matches.first else { return nil }
            return Heading(module: "\(target.module)::doctest/\(target.name)", isDoctest: true)
        }
        guard let parts = captures(headingPattern, line) else { return nil }
        let binary = URL(fileURLWithPath: parts[1]).lastPathComponent
            .replacingOccurrences(of: #"-[0-9a-f]{16}(?:\.exe)?$"#, with: "", options: .regularExpression)
        let matches = targets.filter { target in
            let source = parts[0].hasPrefix("/") ? parts[0] : target.packageDirectory + "/" + parts[0]
            return (target.name == binary || target.name.replacingOccurrences(of: "-", with: "_") == binary)
                && target.source == source
        }
        guard matches.count == 1, let target = matches.first else { return nil }
        return Heading(module: target.module, isDoctest: false)
    }

    private static func sections(_ lines: [String]) -> [Section]? {
        var sections: [Section] = []
        var expected: Int?
        var tests: [Test] = []
        var total = 0
        for line in lines {
            if let values = captures(runningPattern, line) {
                guard expected == nil, let count = Int(values[0]), count <= 100_000 else { return nil }
                expected = count
                tests = []
            } else if expected != nil, let values = captures(testPattern, line) {
                guard tests.count < (expected ?? 0), values[0].utf8.count <= 4096 else { return nil }
                let name = values[0].replacingOccurrences(
                    of: #" - (?:should panic|compile fail|compile)$"#,
                    with: "",
                    options: .regularExpression
                )
                tests.append(Test(
                    name: name,
                    status: values[1] == "ok" ? "success" : values[1] == "FAILED" ? "failure" : "skipped"
                ))
            } else if let values = captures(summaryPattern, line) {
                var counts: [String: Int] = [:]
                for test in tests {
                    counts[test.status, default: 0] += 1
                }
                guard let count = expected, tests.count == count,
                      Int(values[1]) == counts["success", default: 0],
                      Int(values[2]) == counts["failure", default: 0],
                      Int(values[3]) == counts["skipped", default: 0],
                      (values[0] == "FAILED") == (counts["failure", default: 0] > 0),
                      let seconds = Double(values[4]), seconds.isFinite, seconds <= Double(Int32.max) / 1000,
                      total + tests.count <= 100_000, sections.count < 1000 else { return nil }
                total += tests.count
                sections.append(Section(tests: tests, duration: CargoCommandService.milliseconds(seconds)))
                tests = []
                expected = nil
            } else if line.hasPrefix("all doctests ran in ") {
                guard expected == nil, !sections.isEmpty else { return nil }
                sections[sections.count - 1].doctestFooter = true
            }
        }
        return expected == nil ? sections : nil
    }

    private static func assign(_ sections: [Section], to headings: [Heading]) -> [[Section]]? {
        // stdout and stderr are independent pipes. Align completed suites after both drain,
        // rather than relying on the delivery order of Cargo's stderr headings. Edition 2024
        // rustdoc can print several libtest summaries followed by one merged-doctest footer.
        var paths: [[Range<Int>]] = [[]]
        var work = 0
        for heading in headings {
            var next: [[Range<Int>]] = []
            for path in paths {
                let start = path.last?.upperBound ?? 0
                guard start < sections.count else { continue }
                var ends = [start + 1]
                if heading.isDoctest, let footer = sections[start...].firstIndex(where: \.doctestFooter), footer > start {
                    ends.append(footer + 1)
                }
                for end in ends {
                    work += 1
                    guard work <= 10000 else { return nil }
                    let group = sections[start ..< end]
                    if !heading.isDoctest, group.contains(where: \.doctestFooter) { continue }
                    if heading.isDoctest, !group.flatMap(\.tests).allSatisfy({ $0.name.contains(" (line ") }) { continue }
                    next.append(path + [start ..< end])
                }
            }
            paths = next
        }
        let complete = paths.filter { $0.last?.upperBound == sections.count }
        guard complete.count == 1, let path = complete.first else { return nil }
        return path.map { Array(sections[$0]) }
    }
}
