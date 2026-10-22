import FileSystem
import FileSystemTesting
import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import Synchronization
import Testing
import TuistServer
@testable import TuistCargoCommand

struct CargoShardDownloadTests {
    private let transfer = RetryingURLTransfer(
        urlSession: ScriptedArchiveStorage.session,
        retryProvider: RetryProvider(delayProvider: DelayProvider(baseDelayMilliseconds: 0))
    )

    @Test(.inTemporaryDirectory, arguments: [ScriptedArchiveStorage.Step.dropConnection, .status(503)])
    func downloads_the_archive_again_after_a_transient_failure(failure: ScriptedArchiveStorage.Step) async throws {
        let archive = try #require(FileSystem.temporaryTestDirectory).appending(component: "tests.tar.zst")
        let url = ScriptedArchiveStorage.script([failure, .status(200)])

        try await CargoShardService.downloadArchive(from: url, to: archive.url, transfer: transfer)

        #expect(try await FileSystem().readTextFile(at: archive) == "archive")
        #expect(ScriptedArchiveStorage.attempts(url) == 2)
    }

    @Test(.inTemporaryDirectory, arguments: [403, 404])
    func does_not_download_an_archive_storage_rejected_again(statusCode: Int) async throws {
        let archive = try #require(FileSystem.temporaryTestDirectory).appending(component: "tests.tar.zst")
        let url = ScriptedArchiveStorage.script([.status(statusCode), .status(200)])

        let error = await #expect(throws: CargoReportError.self) {
            try await CargoShardService.downloadArchive(from: url, to: archive.url, transfer: transfer)
        }

        #expect(error?.message == "Downloading the nextest shard archive failed.")
        #expect(ScriptedArchiveStorage.attempts(url) == 1)
    }
}

/// Storage that answers each URL it scripted with the next of its steps, serving "archive" on success.
final class ScriptedArchiveStorage: URLProtocol {
    enum Step: Sendable, CustomTestStringConvertible {
        case status(Int)
        case dropConnection

        var testDescription: String {
            switch self {
            case let .status(code): "HTTP \(code)"
            case .dropConnection: "connection dropped"
            }
        }
    }

    private static let scripts = Mutex<[String: [Step]]>([:])
    private static let requests = Mutex<[String: Int]>([:])

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ScriptedArchiveStorage.self]
        return URLSession(configuration: configuration)
    }()

    static func script(_ steps: [Step]) -> URL {
        let url = URL(string: "https://storage.test/\(UUID().uuidString)")!
        scripts.withLock { $0[url.path] = steps }
        return url
    }

    static func attempts(_ url: URL) -> Int {
        requests.withLock { $0[url.path] ?? 0 }
    }

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let path = request.url!.path
        Self.requests.withLock { $0[path, default: 0] += 1 }
        let step = Self.scripts.withLock { scripts in
            scripts[path]?.isEmpty == false ? scripts[path]!.removeFirst() : .status(200)
        }
        switch step {
        case .dropConnection:
            client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost))
        case let .status(code):
            let response = HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data("archive".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
