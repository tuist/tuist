import Combine
import CombineExt

public extension AnyPublisher {
    init(value: Output) {
        self = AnyPublisher.create { subscriber in
            subscriber.send(value)
            subscriber.send(completion: .finished)
            return AnyCancellable {}
        }
    }

    init(error: Failure) {
        self = AnyPublisher.create { subscriber in
            subscriber.send(completion: .failure(error))
            return AnyCancellable {}
        }
    }

    init(result: Result<Output, Failure>) {
        self = AnyPublisher.create { subscriber in
            switch result {
            case let .success(value):
                subscriber.send(value)
                subscriber.send(completion: .finished)
            case let .failure(error):
                subscriber.send(completion: .failure(error))
            }
            return AnyCancellable {}
        }
    }
}
