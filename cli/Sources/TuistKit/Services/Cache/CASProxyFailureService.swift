import FileSystem
import Foundation
import Mockable
import Path
import TuistAlert
import TuistEnvironment

/// A request the Xcode cache proxy failed during a build, as the CAS plugin recorded it.
struct CASProxyFailure: Decodable, Equatable {
    let socket: String
    let error: String
}

@Mockable
protocol CASProxyFailureServicing {
    /// The failure the CAS plugin recorded at or after `date`, or `nil` when it recorded none.
    func failure(since date: Date) async throws -> CASProxyFailure?
}

/// Reads the record `cas-plugin` writes beside the proxy socket when a compiler process gets no answer from
/// the proxy. Inside the build that failure degrades to a cache miss, so a build without a remote cache
/// otherwise looks like one with a cold cache.
struct CASProxyFailureService: CASProxyFailureServicing {
    static let recordFileName = "cas-proxy-failure.json"

    private let fileSystem: FileSysteming

    init(fileSystem: FileSysteming = FileSystem()) {
        self.fileSystem = fileSystem
    }

    func failure(since date: Date) async throws -> CASProxyFailure? {
        let recordPath = Environment.current.casProxySocketPath().parentDirectory
            .appending(component: Self.recordFileName)
        guard let metadata = try await fileSystem.fileMetadata(at: recordPath),
              metadata.lastModificationDate >= date
        else { return nil }
        return try await fileSystem.readJSONFile(at: recordPath)
    }
}

extension CASProxyFailureServicing {
    /// Warns when the proxy failed during the build that started at `date`.
    func warnIfFailed(since date: Date) async {
        guard let failure = try? await failure(since: date) else { return }
        AlertController.current.warning(
            .alert(
                "The Xcode cache proxy at \(failure.socket) failed during this build: \(failure.error)",
                takeaway: "Compilations that needed it used the local cache only, with no remote cache hits or uploads. Run \(.command("tuist setup cache")) if the proxy is not running."
            )
        )
    }
}
