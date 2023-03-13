import Combine
import Foundation

extension Publisher where Output == SystemEvent<Data>, Failure == Error {
    /// Returns another observable where the standard output and error data are mapped
    /// to a string.
    public func mapToString() -> AnyPublisher<SystemEvent<String>, Error> {
        map { $0.mapToString() }.eraseToAnyPublisher()
    }
}

extension Publisher where Output == SystemEvent<String>, Failure == Error {
    public func print() -> AnyPublisher<SystemEvent<String>, Error> {
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
    public func printStandardError() -> AnyPublisher<SystemEvent<String>, Error> {
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
    public func collectAndMergeOutput() -> AnyPublisher<String, Error> {
        reduce("") { collected, event -> String in
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
    public func collectOutput() -> AnyPublisher<SystemCollectedOutput, Error> {
        reduce(SystemCollectedOutput()) { collected, event -> SystemCollectedOutput in
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
}

extension Publisher {
    public var stream: AsyncThrowingStream<Output, Error> {
        AsyncThrowingStream(Output.self) { continuation in
            let cancellable = sink { completion in
                switch completion {
                case .finished:
                    continuation.finish()
                case let .failure(error):
                    continuation.finish(throwing: error)
                }
            } receiveValue: { output in
                continuation.yield(output)
            }

            continuation.onTermination = { @Sendable [cancellable] _ in
                cancellable.cancel()
            }
        }
    }
}
