import Foundation

/// The tests a run could have executed, listed before or after it without running them
/// (`xcodebuild -enumerate-tests`). A run's filters (`-only-testing`, `-skip-testing`) do not
/// narrow the list, so it is the candidate set a selective run chose from. The client writes it
/// into the result bundle as ``fileName``, so whoever parses the bundle, the client in local mode
/// or the server's processor, reports the same list with the run.
public struct TestEnumeration: Codable, Equatable, Sendable {
    public static let fileName = "tuist_test_enumeration.json"

    public struct Test: Codable, Equatable, Hashable, Sendable {
        /// The test target (bundle name), the module of the test case on the server.
        public var module: String
        /// The suite that declares the test, named as the result bundle's parser names it: the
        /// innermost one for nested Swift Testing suites, so the two agree on a test's identity.
        /// Empty for a Swift Testing function declared at file scope.
        public var suite: String
        /// The test's name as Xcode reports it: `testAdd()`, `parameterized(value:)`.
        public var name: String
        /// False when the scheme or the test plan disables the test.
        public var enabled: Bool
        /// The test's function, `map()`, when ``name`` is the display name the run reports it
        /// under instead (see ``TestEnumeration/named(after:)``).
        public var function: String?

        public init(module: String, suite: String, name: String, enabled: Bool, function: String? = nil) {
            self.module = module
            self.suite = suite
            self.name = name
            self.enabled = enabled
            self.function = function
        }

        /// A test from one of xcodebuild's flat identifiers: `Target/Suite/test()`,
        /// `Target/Outer/Nested/test()`, or `Target/test()` for a test outside any suite. Nil for
        /// an identifier with no test component, and for `Target/Class`, which is how xcodebuild
        /// lists a test class that declares no tests of its own, like a shared `XCTestCase` base
        /// class: a test at file scope is always a function, so it carries a parameter list.
        public init?(identifier: String, enabled: Bool) {
            let components = Self.components(of: identifier)
            guard components.count >= 2, let name = components.last, !name.isEmpty else { return nil }
            guard components.count > 2 || name.hasSuffix(")") else { return nil }
            self.init(
                module: components[0],
                suite: components.count >= 3 ? components[components.count - 2] : "",
                name: name,
                enabled: enabled
            )
        }

        /// Splits on the slashes between components, leaving the ones inside a parameter list
        /// alone (a Swift Testing name may carry labels, never slashes, but an argument label
        /// list closes with `)` and nothing follows it).
        private static func components(of identifier: String) -> [String] {
            var components: [String] = []
            var current = ""
            var depth = 0
            for character in identifier {
                switch character {
                case "(": depth += 1; current.append(character)
                case ")": depth = max(0, depth - 1); current.append(character)
                case "/" where depth == 0:
                    components.append(current)
                    current = ""
                default: current.append(character)
                }
            }
            components.append(current)
            return components
        }
    }

    public var tests: [Test]

    public init(tests: [Test]) {
        self.tests = tests
    }

    /// The tests of xcodebuild's JSON output (`-test-enumeration-style flat
    /// -test-enumeration-format json`): one entry per test plan, each with its enabled and
    /// disabled tests. A test that several plans list counts once, enabled when any plan enables
    /// it.
    public init(xcodebuildOutput data: Data) throws {
        let output = try JSONDecoder().decode(XcodebuildOutput.self, from: data)
        var enabledByTest: [Test: Bool] = [:]
        var order: [Test] = []
        for value in output.values {
            let entries = (value.enabledTests ?? []).map { ($0.identifier, true) }
                + (value.disabledTests ?? []).map { ($0.identifier, false) }
            for (identifier, enabled) in entries {
                guard let key = Test(identifier: identifier, enabled: true) else { continue }
                if enabledByTest[key] == nil { order.append(key) }
                enabledByTest[key] = (enabledByTest[key] ?? false) || enabled
            }
        }
        tests = order.map {
            Test(module: $0.module, suite: $0.suite, name: $0.name, enabled: enabledByTest[$0] ?? true)
        }
    }

    /// The enumeration with each test named the way the run's results name it.
    ///
    /// Swift Testing reports a test declared with a display name (`@Test("Maps paths") func
    /// map()`) under that name, while `-enumerate-tests` lists its function, so the same test
    /// would be two test cases: one enumerated and never run, the other run and never
    /// enumerated. The results carry both names, so a test the run executed takes its display
    /// name and keeps its function. One it did not execute keeps the function as its name, for
    /// the server to resolve from an earlier run that did.
    public func named(after testCases: [TestCase]) -> TestEnumeration {
        var displayNames: [Test: String] = [:]
        for testCase in testCases {
            guard let identifier = testCase.identifier, let module = testCase.module else { continue }
            let key = Test(module: module, suite: testCase.testSuite ?? "", name: identifier, enabled: true)
            if displayNames[key] == nil { displayNames[key] = testCase.name }
        }
        guard !displayNames.isEmpty else { return self }
        return TestEnumeration(tests: tests.map { test in
            let key = Test(module: test.module, suite: test.suite, name: test.name, enabled: true)
            guard let displayName = displayNames[key] else { return test }
            return Test(module: test.module, suite: test.suite, name: displayName, enabled: test.enabled, function: test.name)
        })
    }

    /// The enumeration a client wrote into the bundle, or nil when it did not.
    public static func read(fromResultBundle path: URL) -> TestEnumeration? {
        let file = path.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(TestEnumeration.self, from: data)
    }

    public func write(toResultBundle path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: path.appendingPathComponent(Self.fileName), options: .atomic)
    }

    private struct XcodebuildOutput: Decodable {
        struct Value: Decodable {
            struct Entry: Decodable { let identifier: String }
            let enabledTests: [Entry]?
            let disabledTests: [Entry]?
        }

        let values: [Value]
    }
}

extension TestSummary {
    /// The summary with the run's candidate tests attached.
    public func applying(enumeration: TestEnumeration?) -> TestSummary {
        guard let enumeration else { return self }
        var summary = self
        summary.enumeratedTests = enumeration.named(after: testCases).tests
        return summary
    }
}
