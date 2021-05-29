import Foundation
import struct TSCUtility.Version
import TuistSupport
import XCTest

public final class MockXcodeController: XcodeControlling {
    public var selectedStub: Result<Xcode, Error>?
    public var selectedVersionStub: Result<Version, Error> = .success(Version(0, 0, 0))

    public func selected() throws -> Xcode? {
        guard let selectedStub = selectedStub else { return nil }

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
