import Foundation
import RxSwift
import TSCBasic
import TuistCore
import TuistSupport

typealias AsyncQueueEventTuple = (dispatcherId: String, id: UUID, date: Date, data: Data, filename: String)

protocol AsyncQueuePersisting {
    /// Reads all the persisted events and returns them.
    func readAll() -> Single<[AsyncQueueEventTuple]>

    /// Persiss a given event.
    /// - Parameter event: Event to be persisted.
    func write<T: AsyncQueueEvent>(event: T) -> Completable

    /// Deletes the given event from disk.
    /// - Parameter event: Event to be deleted.
    func delete<T: AsyncQueueEvent>(event: T) -> Completable

    /// Deletes the given file name from disk.
    /// - Parameter filename: Name of the file to be deleted.
    func delete(filename: String) -> Completable
}

final class AsyncQueuePersistor: AsyncQueuePersisting {
    // MARK: - Attributes

    let directory: AbsolutePath
    let jsonEncoder: JSONEncoder = JSONEncoder()

    // MARK: - Init

    init(directory: AbsolutePath = Environment.shared.queueDirectory) {
        self.directory = directory
    }

    func write<T: AsyncQueueEvent>(event: T) -> Completable {
        Completable.create { (observer) -> Disposable in
            let path = self.directory.appending(component: self.filename(event: event))
            do {
                let data = try self.jsonEncoder.encode(event)
                try data.write(to: path.url)
                observer(.completed)
            } catch {
                observer(.error(error))
            }
            return Disposables.create()
        }
    }

    func delete<T: AsyncQueueEvent>(event: T) -> Completable {
        delete(filename: filename(event: event))
    }

    func delete(filename: String) -> Completable {
        Completable.create { (observer) -> Disposable in
            let path = self.directory.appending(component: filename)
            guard FileHandler.shared.exists(path) else { return Disposables.create() }
            do {
                try FileHandler.shared.delete(path)
                observer(.completed)
            } catch {
                observer(.error(error))
            }
            return Disposables.create()
        }
    }

    func readAll() -> Single<[AsyncQueueEventTuple]> {
        Single.create { (observer) -> Disposable in
            let paths = FileHandler.shared.glob(self.directory, glob: "*.json")
            var events: [AsyncQueueEventTuple] = []
            paths.forEach { eventPath in
                let fileName = eventPath.basenameWithoutExt
                let components = fileName.split(separator: ".")
                guard components.count == 3,
                    let timestamp = Double(components[0]),
                    let id = UUID(uuidString: String(components[2]))
                else {
                    /// Changing the naming convention is a breaking change. When detected
                    /// we delete the event.
                    try? FileHandler.shared.delete(eventPath)
                    return
                }
                do {
                    let data = try Data(contentsOf: eventPath.url)
                    let event = (dispatcherId: String(components[1]),
                                 id: id,
                                 date: Date(timeIntervalSince1970: timestamp),
                                 data: data,
                                 filename: eventPath.basename)
                    events.append(event)
                } catch {
                    try? FileHandler.shared.delete(eventPath)
                }
            }
            observer(.success(events))
            return Disposables.create()
        }
    }

    // MARK: - Private

    private func filename<T: AsyncQueueEvent>(event: T) -> String {
        "\(Int(event.date.timeIntervalSince1970)).\(event.dispatcherId).\(event.id.uuidString).json"
    }
}
