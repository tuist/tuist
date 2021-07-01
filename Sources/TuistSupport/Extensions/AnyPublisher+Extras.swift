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
}
