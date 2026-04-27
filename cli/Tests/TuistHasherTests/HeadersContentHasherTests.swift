import Foundation
import Path
import TuistCore
import TuistEnvironment
import TuistEnvironmentTesting
import TuistSupport
import TuistTesting
import TuistThreadSafe
import XcodeGraph
import XCTest

@testable import TuistHasher

private final class ConcurrencySafeContentHashingStub: ContentHashing {
    private let pathHashCalls = ThreadSafe<[AbsolutePath]>([])
    private let pathHashMapping: [AbsolutePath: String]
    private let stringsHashSeparator: String

    init(pathHashMapping: [AbsolutePath: String], stringsHashSeparator: String = ";") {
        self.pathHashMapping = pathHashMapping
        self.stringsHashSeparator = stringsHashSeparator
    }

    var pathHashInvocationCount: Int { pathHashCalls.value.count }

    func hash(path: AbsolutePath) async throws -> String {
        pathHashCalls.mutate { $0.append(path) }
        return pathHashMapping[path] ?? ""
    }

    func hash(_: Data) throws -> String { unimplemented() }
    func hash(_: String) throws -> String { unimplemented() }
    func hash(_: Bool) throws -> String { unimplemented() }
    func hash(_ strings: [String]) throws -> String { strings.joined(separator: stringsHashSeparator) }
    func hash(_: [String: String]) throws -> String { unimplemented() }

    private func unimplemented(function: StaticString = #function) -> Never {
        fatalError("\(function) is not stubbed in ConcurrencySafeContentHashingStub")
    }
}

final class HeadersContentHasherTests: TuistUnitTestCase {
    private let filePath1 = try! AbsolutePath(validating: "/file1")
    private let filePath2 = try! AbsolutePath(validating: "/file2")
    private let filePath3 = try! AbsolutePath(validating: "/file3")
    private let filePath4 = try! AbsolutePath(validating: "/file4")
    private let filePath5 = try! AbsolutePath(validating: "/file5")
    private let filePath6 = try! AbsolutePath(validating: "/file6")

    private var pathHashMapping: [AbsolutePath: String] {
        [
            filePath1: "1",
            filePath2: "2",
            filePath3: "3",
            filePath4: "4",
            filePath5: "5",
            filePath6: "6",
        ]
    }

    private var headers: Headers {
        Headers(
            public: [filePath1, filePath2],
            private: [filePath3, filePath4],
            project: [filePath5, filePath6]
        )
    }

    func test_hash_withLegacyBackend_preservesInputOrder() async throws {
        try await withMockedEnvironment {
            // Given
            Environment.mocked?.variables["TUIST_FILESYSTEM_BACKEND"] = "legacy"
            let stub = ConcurrencySafeContentHashingStub(pathHashMapping: pathHashMapping)
            let subject = HeadersContentHasher(contentHasher: stub)

            // When
            let hash = try await subject.hash(headers: headers)

            // Then
            XCTAssertEqual(hash, "1;2;3;4;5;6")
            XCTAssertEqual(stub.pathHashInvocationCount, 6)
        }
    }

    func test_hash_withSwiftFileSystemBackend_preservesInputOrder() async throws {
        try await withMockedEnvironment {
            // Given
            Environment.mocked?.variables["TUIST_FILESYSTEM_BACKEND"] = "swift-file-system"
            let stub = ConcurrencySafeContentHashingStub(pathHashMapping: pathHashMapping)
            let subject = HeadersContentHasher(contentHasher: stub)

            // When
            let hash = try await subject.hash(headers: headers)

            // Then
            XCTAssertEqual(hash, "1;2;3;4;5;6")
            XCTAssertEqual(stub.pathHashInvocationCount, 6)
        }
    }
}
