import Foundation
import MockableTest
import Path
import TuistCore
import TuistSupport
import TuistSupportTesting
import XcodeGraph
import XCTest

@testable import TuistHasher

final class ResourcesContentHasherTests: TuistUnitTestCase {
    private var subject: ResourcesContentHasher!
    private var contentHasher: ContentHasher!
    private let filePath1 = try! AbsolutePath(validating: "/file1")
    private let filePath2 = try! AbsolutePath(validating: "/file2")

    override func setUp() {
        super.setUp()
        contentHasher = ContentHasher()
        subject = ResourcesContentHasher(contentHasher: contentHasher)
    }

    override func tearDown() {
        subject = nil
        contentHasher = nil
        super.tearDown()
    }

    func test_hash_returnsAValidTree() throws {}
}
