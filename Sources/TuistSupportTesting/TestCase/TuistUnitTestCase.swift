import FileSystem
import Foundation
import XCTest

@testable import TuistSupport

open class TuistUnitTestCase: TuistTestCase {
    public var system: MockSystem!
    public var fileSystem: FileSysteming!

    override open func setUp() {
        super.setUp()
        // System
        system = MockSystem()
        System._shared.mutate { $0 = system }

        fileSystem = FileSystem()
    }

    override open func tearDown() {
        // System
        system = nil
        System._shared.mutate { $0 = System() }

        fileSystem = nil

        super.tearDown()
    }
}
