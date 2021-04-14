import Foundation
import RxSwift

public extension Observable where Element == SystemEvent<Data> {
    /// Returns another observable where the standard output and error data are mapped
    /// to a string.
    func mapToString() -> Observable<SystemEvent<String>> {
        map { $0.mapToString() }
    }
}

public extension Observable where Element == SystemEvent<String> {
    func print() -> Observable<SystemEvent<String>> {
        `do`(onNext: { (event: SystemEvent<String>) in
            switch event {
            case let .standardError(error):
                logger.error("\(error)")
            case let .standardOutput(output):
                logger.info("\(output)")
            }
        })
    }

    /// Returns an observable that prints the standard error.
    func printStandardError() -> Observable<SystemEvent<String>> {
        `do`(onNext: { event in
            switch event {
            case let .standardError(error):
                if let data = error.data(using: .utf8) {
                    FileHandle.standardError.write(data)
                }
            default:
                return
            }
        })
    }

    /// Returns an observable that collects and merges the standard output and error into a single string.
    func collectAndMergeOutput() -> Observable<String> {
        reduce("") { (collected, event) -> String in
            var collected = collected
            switch event {
            case let .standardError(error):
                collected.append(error)
            case let .standardOutput(output):
                collected.append(output)
            }
            return collected
        }
    }

    /// It collects the standard output and error into an object that is sent
    /// as a single event when the process completes.
    func collectOutput() -> Observable<SystemCollectedOutput> {
        reduce(SystemCollectedOutput()) { (collected, event) -> SystemCollectedOutput in
            var collected = collected
            switch event {
            case let .standardError(error):
                collected.standardError.append(error)
            case let .standardOutput(output):
                collected.standardOutput.append(output)
            }
            return collected
        }
    }

    /// Returns an observable that forwards the system events filtering the standard output ones using the given function.
    /// - Parameter filter: Function to filter the standard output events.
    func filterStandardOutput(_ filter: @escaping (String) -> Bool) -> Observable<SystemEvent<String>> {
        self.filter {
            if case let SystemEvent.standardOutput(output) = $0 {
                return filter(output)
            } else {
                return true
            }
        }
    }

    /// Returns an observable that forwards all the system except the standard output ones rejected by the given function.
    /// - Parameter rejector: Function to reject standard output events.
    func rejectStandardOutput(_ rejector: @escaping (String) -> Bool) -> Observable<SystemEvent<String>> {
        filter {
            if case let SystemEvent.standardOutput(output) = $0 {
                return !rejector(output)
            } else {
                return true
            }
        }
    }

    /// Returns an observable that forwards the system events filtering the standard error ones using the given function.
    /// - Parameter filter: Function to filter the standard error events.
    func filterStandardError(_ filter: @escaping (String) -> Bool) -> Observable<SystemEvent<String>> {
        self.filter {
            if case let SystemEvent.standardError(error) = $0 {
                return filter(error)
            } else {
                return true
            }
        }
    }

    /// Returns an observable that forwards all the system except the standard error ones rejected by the given function.
    /// - Parameter rejector: Function to reject standard error events.
    func rejectStandardError(_ rejector: @escaping (String) -> Bool) -> Observable<SystemEvent<String>> {
        filter {
            if case let SystemEvent.standardError(error) = $0 {
                return !rejector(error)
            } else {
                return true
            }
        }
    }
}
