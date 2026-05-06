#if os(macOS)
    import FileSystem
    import Foundation
    import XCTest

    open class TuistUnitTestCase: TuistTestCase {
        public var mockCommandRunner: MockCommandRunner!
        public var fileSystem: FileSysteming!

        override open func setUp() {
            super.setUp()
            mockCommandRunner = MockCommandRunner()

            fileSystem = FileSystem()
        }

        override open func tearDown() {
            mockCommandRunner = nil
            fileSystem = nil

            super.tearDown()
        }
    }
#endif
