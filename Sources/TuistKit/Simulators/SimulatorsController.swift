import Foundation
import TuistCore
import TuistSupport

enum SimulatorControllerError: FatalError {
    /// Thrown when the simctl output can't be turned into a Data object.
    case nilDataFromOutput(arguments: [String])

    /// Thrown when the output from simctl can't be JSON-decoded
    case jsonDecoding(arguments: [String], error: Error)

    /// Thrown when the output is not a expected dictionary.
    case notADictionary(arguments: [String])

    /// Thrown when a key is missing from the decoded object.
    case missingKey(String, arguments: [String])

    var type: ErrorType {
        switch self {
        case .nilDataFromOutput: return .bug
        case .jsonDecoding: return .bug
        case .notADictionary: return .bug
        case .missingKey: return .bug
        }
    }

    var description: String {
        switch self {
        case let .nilDataFromOutput(arguments):
            return "Couldn't turn the output from 'simctl \(arguments.joined(separator: " "))' into data"
        case let .jsonDecoding(arguments, error):
            return "Could not JSON-decode the output returned by 'simctl \(arguments.joined(separator: " "))': \(error)"
        case let .notADictionary(arguments):
            return "The output from 'simctl \(arguments.joined(separator: " "))' is not a dictionary"
        case let .missingKey(key, arguments):
            return "The output from 'simctl \(arguments.joined(separator: " "))' does not have the key \(key) or has an invalid format"
        }
    }
}

protocol SimulatorsControlling {
    /// Returns the list of runtimes available in the system.
    /// - Returns: A list of simulator runtimes.
    func runtimes() throws -> [SimulatorRuntime]
}

final class SimulatorsController: SimulatorsControlling {
    /// JSON decoder instance.
    fileprivate let jsonDecoder: JSONDecoder = JSONDecoder()

    // MARK: - Internal

    func runtimes() throws -> [SimulatorRuntime] {
        let arguments = ["list", "runtimes", "-j"]
        let dictionary = try captureSimctlJSON(arguments)
        guard let runtimes = dictionary["runtimes"] as? [Any] else {
            throw SimulatorControllerError.missingKey("runtimes", arguments: arguments)
        }
        let data = try JSONSerialization.data(withJSONObject: runtimes, options: [])
        return try jsonDecoder.decode([SimulatorRuntime].self, from: data)
    }

    // MARK: - Fileprivate

    fileprivate func captureSimctlJSON(_ arguments: [String]) throws -> [String: Any] {
        let output = try captureSimctl(arguments)

        guard let data = output.data(using: .utf8) else {
            throw SimulatorControllerError.nilDataFromOutput(arguments: arguments)
        }

        var json: Any!
        do {
            json = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw SimulatorControllerError.jsonDecoding(arguments: arguments, error: error)
        }
        guard let dictionary = json as? [String: Any] else {
            throw SimulatorControllerError.notADictionary(arguments: arguments)
        }
        return dictionary
    }

    fileprivate func captureSimctl(_ arguments: [String]) throws -> String {
        var arguments = arguments
        arguments.insert(contentsOf: ["xcrun", "simctl"], at: 0)
        return try System.shared.capture(arguments)
    }
}
