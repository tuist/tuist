import Foundation
import struct TSCUtility.Version
import TuistSupport
import XCTest

public final class MockXcodeController: XcodeControlling, @unchecked Sendable {
    public var selectedStub: Result<Xcode, Error>? {
        get {
            _selectedStub.value
        }
        set {
            _selectedStub.mutate { $0 = newValue }
        }
    }

    private var _selectedStub: ThreadSafe<Result<Xcode, Error>?> = ThreadSafe(nil)

    public var selectedVersionStub: Result<Version, Error> {
        get {
            _selectedVersionStub.value
        }
        set {
            _selectedVersionStub.mutate { $0 = newValue }
        }
    }

    public let _selectedVersionStub: ThreadSafe<Result<Version, Error>> = ThreadSafe(.success(Version(0, 0, 0)))

    public func selected() throws -> Xcode? {
        guard let selectedStub else { return nil }

        switch selectedStub {
        case let .failure(error): throw error
        case let .success(xcode): return xcode
        }
    }

    public func selectedVersion() throws -> Version {
        switch selectedVersionStub {
        case let .failure(error): throw error
        case let .success(version): return version
        }
    }
}
