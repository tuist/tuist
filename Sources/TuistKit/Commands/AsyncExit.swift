import Combine
import Foundation

/// `TuistProcess` is a wrapper on top of the cli command to provide
/// an asynchronous way to exit the process, which waits for all `futureTask`
/// to be completed, with a maximum threshold of time of `maximumWaitingTime` seconds
final class TuistProcess {
    static let shared = TuistProcess()

    private var futureTasks: [Future<Void, Never>] = []
    private let maximumWaitingTime = DispatchTimeInterval.seconds(2)

    private init() {}

    /// `add` a task that needs to complete before tuist process ends.
    /// Note that tasks will only have `maximumWaitingTime` seconds to complete
    /// after tuist is ready to exit, otherwise they will be canceled
    func add(futureTask: Future<Void, Never>) {
        futureTasks.append(futureTask)
    }

    /// `asyncExit` will make sure that all important async tasks
    /// complete before it `exit`s the process
    func asyncExit(_ code: Int32 = 0) -> Never {
        let dispatchGroup = DispatchGroup()
        dispatchGroup.enter()
        let cancellable = Publishers.MergeMany(futureTasks).collect().sink { _ in
            dispatchGroup.leave()
        }
        // Set `maximumWaitingTime` seconds as a parachute timeout in case something
        // goes wrong and events don't cmoplete: we don't want tuist's
        // process to hang forever
        _ = dispatchGroup.wait(timeout: DispatchTime.now() + maximumWaitingTime)
        cancellable.cancel()
        exit(code)
    }
}
