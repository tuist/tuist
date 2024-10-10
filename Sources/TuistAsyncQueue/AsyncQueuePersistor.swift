import FileSystem
import Foundation
import Path
import TuistCore
import TuistSupport

// swiftlint:disable:next large_tuple
public typealias AsyncQueueEventTuple = (dispatcherId: String, id: UUID, date: Date, data: Data, filename: String)

public protocol AsyncQueuePersisting {
    /// Reads all the persisted events and returns them.
    func readAll() async throws -> [AsyncQueueEventTuple]

    /// Persiss a given event.
    /// - Parameter event: Event to be persisted.
    func write<T: AsyncQueueEvent>(event: T) throws

    /// Deletes the given event from disk.
    /// - Parameter event: Event to be deleted.
    func delete<T: AsyncQueueEvent>(event: T) async throws

    /// Deletes the given file name from disk.
    /// - Parameter filename: Name of the file to be deleted.
    func delete(filename: String) async throws
}

final class AsyncQueuePersistor: AsyncQueuePersisting {
    // MARK: - Attributes

    private let directory: AbsolutePath
    private let jsonEncoder = JSONEncoder()
    private let fileSystem: FileSystem
    private let dateService: DateServicing

    // MARK: - Init

    init(
        directory: AbsolutePath = Environment.shared.queueDirectory,
        fileSystem: FileSystem = FileSystem(),
        dateService: DateServicing = DateService()
    ) {
        self.directory = directory
        self.fileSystem = fileSystem
        self.dateService = dateService
    }

    func write(event: some AsyncQueueEvent) throws {
        let path = directory.appending(component: filename(event: event))
        try createDirectoryIfNeeded()
        let data = try jsonEncoder.encode(event)
        try data.write(to: path.url)
    }

    func delete(event: some AsyncQueueEvent) async throws {
        try await delete(filename: filename(event: event))
    }

    func delete(filename: String) async throws {
        let path = directory.appending(component: filename)
        guard try await fileSystem.exists(path) else { return }
        try await fileSystem.remove(path)
    }

    func readAll() async throws -> [AsyncQueueEventTuple] {
        let dateService = dateService
        let fileSystem = fileSystem
        let paths = FileHandler.shared.glob(directory, glob: "*.json")
        let events: [AsyncQueueEventTuple] = await paths.concurrentCompactMap { eventPath in
            let fileName = eventPath.basenameWithoutExt
            let components = fileName.split(separator: ".")
            guard components.count == 3,
                  let timestamp = Double(components[0]),
                  let id = UUID(uuidString: String(components[2]))
            else {
                /// Changing the naming convention is a breaking change. When detected
                /// we delete the event.
                try? await fileSystem.remove(eventPath)
                return nil
            }

            // We delete events that are older than a day to ensure the directory doesn't grow indefinitely if events continuosly
            // fail to be uploaded.
            let date = Date(timeIntervalSince1970: timestamp)
            if dateService.now().timeIntervalSince(date) > 24 * 60 * 60 {
                try? await fileSystem.remove(eventPath)
                return nil
            }

            do {
                let data = try Data(contentsOf: eventPath.url)
                let event = (
                    dispatcherId: String(components[1]),
                    id: id,
                    date: date,
                    data: data,
                    filename: eventPath.basename
                )
                return event
            } catch {
                try? await fileSystem.remove(eventPath)
                return nil
            }
        }
        return events
    }

    // MARK: - Private

    private func filename(event: some AsyncQueueEvent) -> String {
        "\(Int(event.date.timeIntervalSince1970)).\(event.dispatcherId).\(event.id.uuidString).json"
    }

    private func createDirectoryIfNeeded() throws {
        guard !FileManager.default.fileExists(atPath: directory.pathString) else { return }
        try FileManager.default.createDirectory(atPath: directory.pathString, withIntermediateDirectories: true)
    }
}
