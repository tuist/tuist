import Command
import Foundation

actor SimulatorPool {
    static let shared = SimulatorPool()

    private let commandRunner = CommandRunner()
    private let poolSize: Int
    private let forcedSimulator: String?
    private let processIdentifier: Int32

    private var initializedModels: Set<String> = []
    private var availableSimulators: [String: [String]] = [:]
    private var waiters: [String: [CheckedContinuation<String, Never>]] = [:]

    init(
        poolSize: Int = SimulatorPool.poolSizeFromEnvironment(),
        forcedSimulator: String? = ProcessInfo.processInfo.environment["TUIST_ACCEPTANCE_SIMULATOR_MODEL"],
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier
    ) {
        self.poolSize = poolSize
        self.forcedSimulator = forcedSimulator?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
        self.processIdentifier = processIdentifier
    }

    func checkout(requestedSimulator: String) async throws -> (identifier: String, model: String) {
        let model = forcedSimulator ?? requestedSimulator
        try await ensurePool(for: model)

        if let identifier = availableSimulators[model]?.popLast() {
            return (identifier: identifier, model: model)
        }

        let identifier = await withCheckedContinuation { continuation in
            waiters[model, default: []].append(continuation)
        }
        return (identifier: identifier, model: model)
    }

    func release(identifier: String, model: String) {
        if var modelWaiters = waiters[model], modelWaiters.isEmpty == false {
            let waiter = modelWaiters.removeFirst()
            waiters[model] = modelWaiters
            waiter.resume(returning: identifier)
        } else {
            availableSimulators[model, default: []].append(identifier)
        }
    }

    private func ensurePool(for model: String) async throws {
        guard initializedModels.contains(model) == false else { return }

        for index in 0 ..< poolSize {
            let identifier = simulatorIdentifier(model: model, index: index)
            _ = try? await commandRunner.run(arguments: ["/usr/bin/xcrun", "simctl", "delete", identifier])
                .pipedStream()
                .awaitCompletion()
            try await commandRunner.run(arguments: ["/usr/bin/xcrun", "simctl", "create", identifier, model])
                .pipedStream()
                .awaitCompletion()
            try await commandRunner.run(arguments: ["/usr/bin/xcrun", "simctl", "boot", identifier])
                .pipedStream()
                .awaitCompletion()
            try await commandRunner.run(arguments: ["/usr/bin/xcrun", "simctl", "bootstatus", identifier, "-b"])
                .pipedStream()
                .awaitCompletion()
            availableSimulators[model, default: []].append(identifier)
        }

        initializedModels.insert(model)
    }

    private func simulatorIdentifier(model: String, index: Int) -> String {
        let sanitizedModel = model.lowercased()
            .map { character in
                if character.isLetter || character.isNumber {
                    return character
                } else {
                    return "-"
                }
            }
        return "tuist-acc-\(processIdentifier)-\(String(sanitizedModel))-\(index)"
    }

    private static func poolSizeFromEnvironment() -> Int {
        guard let value = ProcessInfo.processInfo.environment["TUIST_ACCEPTANCE_SIMULATOR_POOL_SIZE"],
              let parsed = Int(value),
              parsed > 0
        else {
            return 2
        }
        return parsed
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
