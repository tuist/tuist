import Foundation
import RxSwift

extension Observable where Element == SystemEvent<Data> {
    /// Returns another observable where the standard output and error data are mapped
    /// to a string.
    func mapToString() -> Observable<SystemEvent<String>> {
        map { $0.mapToString() }
    }
}

extension Observable where Element == SystemEvent<String> {
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
}
