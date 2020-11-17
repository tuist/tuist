import Foundation
import TSCBasic
import TuistCore
import TuistSupport
import XCTest

@testable import ProjectDescription
@testable import TuistLoader
@testable import TuistLoaderTesting
@testable import TuistSupportTesting

final class DependenciesModelLoaderTests: TuistUnitTestCase {
    private var manifestLoader: MockManifestLoader!
    
    private var subject: DependenciesModelLoader!
    
    override func setUp() {
        super.setUp()
        
        manifestLoader = MockManifestLoader()
        subject = DependenciesModelLoader(manifestLoader: manifestLoader)
    }
    
    override func tearDown() {
        subject = nil
        manifestLoader = nil
        
        super.tearDown()
    }
    
    func test_loadDependencies() throws {
        // Given
        let stubbedPath = try temporaryPath()
        manifestLoader.loadDependenciesStub = { _ in
            Dependencies([
                .carthage(name: "Dependency1", requirement: .exact("1.1.1")),
                .carthage(name: "Dependency2", requirement: .exact("2.3.4")),
            ])
        }
        
        // When
        let models = try subject.loadDependencies(at: stubbedPath)
        let expectedModels: [CarthageDependency] = [
            CarthageDependency(name: "Dependency1", requirement: .exact("1.1.1")),
            CarthageDependency(name: "Dependency2", requirement: .exact("2.3.4"))
        ]
        
        // Then
        XCTAssertEqual(models, expectedModels)
    }
}
