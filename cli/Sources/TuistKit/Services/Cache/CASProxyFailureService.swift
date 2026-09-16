import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistEnvironment

/// A request the Xcode cache proxy failed during a build, as the CAS plugin recorded it.
struct CASProxyFailure: Equatable {
    let socket: String
    let error: String
}

@Mockable
protocol CASProxyFailureServicing {
    /// The most recent failure the CAS plugin recorded at or after `date`, or `nil` when it recorded none.
    func failure(since date: Date) async throws -> CASProxyFailure?
}

/// Reads the records `cas-plugin` writes beside the proxy socket when a process gets no answer from the proxy,
/// one per build and one per build service. Inside the build that failure degrades to a cache miss, so a build
/// without a remote cache otherwise looks like one with a cold cache.
struct CASProxyFailureService: CASProxyFailureServicing {
    static let recordDirectoryName = "cas-proxy-failures"

    private let fileSystem: FileSysteming

    init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    func failure(since date: Date) async throws -> CASProxyFailure? {
        let directory = Environment.current.casProxySocketPath().parentDirectory
            .appending(component: Self.recordDirectoryName)
        guard try await fileSystem.exists(directory) else { return nil }

        let sinceMilliseconds = date.timeIntervalSince1970 * 1000
        var latest: Record?
        for path in try await fileSystem.glob(directory: directory, include: ["*.json"]).collect() {
            guard let record: Record = try? await fileSystem.readJSONFile(at: path),
                  Double(record.failedAtMilliseconds) >= sinceMilliseconds
            else { continue }
            if let current = latest, current.failedAtMilliseconds >= record.failedAtMilliseconds { continue }
            latest = record
        }
        return latest.map { CASProxyFailure(socket: $0.socket, error: $0.error) }
    }

    private struct Record: Decodable {
        let socket: String
        let error: String
        let failedAtMilliseconds: UInt64

        enum CodingKeys: String, CodingKey {
            case socket
            case error
            case failedAtMilliseconds = "failed_at_ms"
        }
    }
}

extension CASProxyFailureServicing {
    /// Warns when the proxy failed during the build that started at `date`.
    func warnIfFailed(since date: Date) async {
        guard let failure = try? await failure(since: date) else { return }
        AlertController.current.warning(
            .alert(
                "The Xcode cache proxy at \(failure.socket) failed during this build: \(failure.error)",
                takeaway: "Compilations that needed it used the local cache only, without remote cache hits. Their uploads are kept on disk and sent once the proxy is reachable again. Run \(.command("tuist setup cache")) if the proxy is not running."
            )
        )
    }
}
