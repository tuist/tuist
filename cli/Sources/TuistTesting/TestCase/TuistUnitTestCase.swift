#if os(macOS)
    import FileSystem
    import Foundation
    import XCTest

    @testable import TuistSupport

    open class TuistUnitTestCase: TuistTestCase {
        public var fileSystem: FileSysteming!

        override open func setUp() {
            super.setUp()
            fileSystem = FileSystem()
        }

        override open func tearDown() {
            fileSystem = nil
            super.tearDown()
        }
    }
#endif
