import Foundation

/// Whether a run executed its tests in parallel or serially, for the run and for each test
/// target. The client derives it from the xcodebuild arguments and the xctestrun and writes it
/// into the result bundle as ``fileName``, so whoever parses the bundle, the client in local mode
/// or the server's processor, records the same answer with the run.
public struct TestExecutionModes: Codable, Equatable, Sendable {
    public static let fileName = "tuist_execution_modes.json"
    public static let parallel = "parallel"
    public static let serial = "serial"

    /// The run's mode: `parallel` when any target ran in parallel, `serial` when every target ran
    /// serially, nil when unknown.
    public var run: String?
    /// The mode per test target (bundle name), for the targets the xctestrun described.
    public var targets: [String: String]

    public init(run: String?, targets: [String: String]) {
        self.run = run
        self.targets = targets
    }

    /// The modes a client wrote into the bundle, or nil when it did not.
    public static func read(fromResultBundle path: URL) -> TestExecutionModes? {
        let file = path.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(TestExecutionModes.self, from: data)
    }

    public func write(toResultBundle path: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: path.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

extension TestSummary {
    /// The summary with the modes applied: the run's, and each module's by name, falling back to
    /// the run's when the xctestrun did not describe the module.
    public func applying(executionModes modes: TestExecutionModes?) -> TestSummary {
        guard let modes else { return self }
        var summary = self
        summary.executionMode = modes.run
        summary.testModules = testModules.map { module in
            var module = module
            module.executionMode = modes.targets[module.name] ?? modes.run
            return module
        }
        return summary
    }
}
