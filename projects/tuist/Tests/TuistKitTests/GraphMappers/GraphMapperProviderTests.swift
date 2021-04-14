import Foundation
import TuistCache
import TuistCloud
import TuistCore
import TuistCoreTesting
import TuistGenerator
import TuistSigning
import TuistSupport
import XCTest

@testable import TuistKit
@testable import TuistSupportTesting

final class GraphMapperProviderTests: TuistUnitTestCase {
    var subject: GraphMapperProvider!

    override func setUp() {
        super.setUp()
        subject = GraphMapperProvider()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }
}
