import Foundation
import TSCBasic
import TuistCore
import TuistSupport

// swiftlint:disable:next large_tuple
public typealias AsyncQueueEventTuple = (dispatcherId: String, id: UUID, date: Date, data: Data, filename: String)

public protocol AsyncQueuePersisting {
    /// Reads all the persisted events and returns them.
    func readAll() throws -> [AsyncQueueEventTuple]

    /// Persiss a given event.
    /// - Parameter event: Event to be persisted.
    func write<T: AsyncQueueEvent>(event: T) throws

    /// Deletes the given event from disk.
    /// - Parameter event: Event to be deleted.
    func delete<T: AsyncQueueEvent>(event: T) throws

    /// Deletes the given file name from disk.
    /// - Parameter filename: Name of the file to be deleted.
    func delete(filename: String) throws
}

final class AsyncQueuePersistor: AsyncQueuePersisting {
    // MARK: - Attributes

    let cacheDirectory: AbsolutePath
    let jsonEncoder = JSONEncoder()
    var queueDirectory: AbsolutePath { cacheDirectory.appending(components: ["Queue"]) }

    // MARK: - Init

    init(cacheDirectory: AbsolutePath = TuistContext.shared.environment.cacheDirectory) {
        self.cacheDirectory = cacheDirectory
    }

    func write(event: some AsyncQueueEvent) throws {
        let path = queueDirectory.appending(component: filename(event: event))
        try createDirectoryIfNeeded()
        let data = try jsonEncoder.encode(event)
        try data.write(to: path.url)
    }

    func delete(event: some AsyncQueueEvent) throws {
        try delete(filename: filename(event: event))
    }

    func delete(filename: String) throws {
        let path = queueDirectory.appending(component: filename)
        guard FileHandler.shared.exists(path) else { return }
        try FileHandler.shared.delete(path)
    }

    func readAll() throws -> [AsyncQueueEventTuple] {
        let paths = FileHandler.shared.glob(queueDirectory, glob: "*.json")
        var events: [AsyncQueueEventTuple] = []
        for eventPath in paths {
            let fileName = eventPath.basenameWithoutExt
            let components = fileName.split(separator: ".")
            guard components.count == 3,
                  let timestamp = Double(components[0]),
                  let id = UUID(uuidString: String(components[2]))
            else {
                /// Changing the naming convention is a breaking change. When detected
                /// we delete the event.
                try? FileHandler.shared.delete(eventPath)
                continue
            }
            do {
                let data = try Data(contentsOf: eventPath.url)
                let event = (
                    dispatcherId: String(components[1]),
                    id: id,
                    date: Date(timeIntervalSince1970: timestamp),
                    data: data,
                    filename: eventPath.basename
                )
                events.append(event)
            } catch {
                try? FileHandler.shared.delete(eventPath)
            }
        }
        return events
    }

    // MARK: - Private

    private func filename(event: some AsyncQueueEvent) -> String {
        "\(Int(event.date.timeIntervalSince1970)).\(event.dispatcherId).\(event.id.uuidString).json"
    }

    private func createDirectoryIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: queueDirectory.pathString) else { return }
        try FileManager.default.createDirectory(atPath: queueDirectory.pathString, withIntermediateDirectories: true)
    }
}
