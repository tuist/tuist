import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest
@testable import TuistCoreTesting
@testable import TuistGenerator
@testable import TuistSupportTesting

final class ResourcesNamespaceProjectMapperTests: TuistUnitTestCase {
    private var subject: ResourcesNamespaceProjectMapper!
    private var namespaceGenerator: MockNamespaceGenerator!
    
    override func setUp() {
        super.setUp()
        
        namespaceGenerator = MockNamespaceGenerator()
        subject = ResourcesNamespaceProjectMapper(
            namespaceGenerator: namespaceGenerator
        )
    }
    
    override func tearDown() {
        super.tearDown()
        
        namespaceGenerator = nil
        subject = nil
    }
}
