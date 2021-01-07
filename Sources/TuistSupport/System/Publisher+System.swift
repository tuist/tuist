import Combine
import CombineExt
import Foundation

public extension Publisher where Output == SystemEvent<Data>, Failure == Error {
    /// Returns another observable where the standard output and error data are mapped
    /// to a string.
    func mapToString() -> AnyPublisher<SystemEvent<String>, Error> {
        map { $0.mapToString() }.eraseToAnyPublisher()
    }
}

public extension Publisher where Output == SystemEvent<String>, Failure == Error {
    func print() -> AnyPublisher<SystemEvent<String>, Error> {
        handleEvents(receiveOutput: { event in
            switch event {
            case let .standardError(error):
                logger.error("\(error)")
            case let .standardOutput(output):
                logger.info("\(output)")
            }
        })
            .eraseToAnyPublisher()
    }

    /// Returns an observable that prints the standard error.
    func printStandardError() -> AnyPublisher<SystemEvent<String>, Error> {
        handleEvents(receiveOutput: { event in
            switch event {
            case let .standardError(error):
                if let data = error.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            default:
                return
            }
        })
            .eraseToAnyPublisher()
    }

    /// Returns an observable that collects and merges the standard output and error into a single string.
    func collectAndMergeOutput() -> AnyPublisher<String, Error> {
        reduce("") { (collected, event) -> String in
            var collected = collected
            switch event {
            case let .standardError(error):
                collected.append(error)
            case let .standardOutput(output):
                collected.append(output)
            }
            return collected
        }.eraseToAnyPublisher()
    }

    /// It collects the standard output and error into an object that is sent
    /// as a single event when the process completes.
    func collectOutput() -> AnyPublisher<SystemCollectedOutput, Error> {
        reduce(SystemCollectedOutput()) { (collected, event) -> SystemCollectedOutput in
            var collected = collected
            switch event {
            case let .standardError(error):
                collected.standardError.append(error)
            case let .standardOutput(output):
                collected.standardOutput.append(output)
            }
            return collected
        }.eraseToAnyPublisher()
    }

    /// Returns an observable that forwards the system events filtering the standard output ones using the given function.
    /// - Parameter filter: Function to filter the standard output events.
    func filterStandardOutput(_ filter: @escaping (String) -> Bool) -> AnyPublisher<SystemEvent<String>, Error> {
        self.filter {
            if case let SystemEvent.standardOutput(output) = $0 {
                return filter(output)
            } else {
                return true
            }
        }.eraseToAnyPublisher()
    }

    /// Returns an observable that forwards all the system except the standard output ones rejected by the given function.
    /// - Parameter rejector: Function to reject standard output events.
    func rejectStandardOutput(_ rejector: @escaping (String) -> Bool) -> AnyPublisher<SystemEvent<String>, Error> {
        filter {
            if case let SystemEvent.standardOutput(output) = $0 {
                return !rejector(output)
            } else {
                return true
            }
        }.eraseToAnyPublisher()
    }

    /// Returns an observable that forwards the system events filtering the standard error ones using the given function.
    /// - Parameter filter: Function to filter the standard error events.
    func filterStandardError(_ filter: @escaping (String) -> Bool) -> AnyPublisher<SystemEvent<String>, Error> {
        self.filter {
            if case let SystemEvent.standardError(error) = $0 {
                return filter(error)
            } else {
                return true
            }
        }.eraseToAnyPublisher()
    }

    /// Returns an observable that forwards all the system except the standard error ones rejected by the given function.
    /// - Parameter rejector: Function to reject standard error events.
    func rejectStandardError(_ rejector: @escaping (String) -> Bool) -> AnyPublisher<SystemEvent<String>, Error> {
        filter {
            if case let SystemEvent.standardError(error) = $0 {
                return !rejector(error)
            } else {
                return true
            }
        }.eraseToAnyPublisher()
    }
}
