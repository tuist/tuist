import TSCBasic
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistSupportTesting

final class SwiftPackageManagerTests: TuistUnitTestCase {
    private var subject: SwiftPackageManager!
    
    override func setUp() {
        super.setUp()

        subject = SwiftPackageManager()
    }

    override func tearDown() {
        subject = nil

        super.tearDown()
    }
    
    func test_resolve() throws {
        // Given
        let path = try temporaryPath()
        system.succeedCommand([
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "resolve"
        ])
        
        // When
        XCTAssertNoThrow(try subject.resolve(at: path))
    }
    
    func test_loadDependencies() throws {
        // Given
        let path = try temporaryPath()
        
        let json = """
        {
          "name": "Foo",
          "url": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests",
          "version": "unspecified",
          "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests",
          "dependencies": [
            {
              "name": "Moya",
              "url": "https://github.com/Moya/Moya.git",
              "version": "14.0.1",
              "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Moya",
              "dependencies": [
                {
                  "name": "Alamofire",
                  "url": "https://github.com/Alamofire/Alamofire.git",
                  "version": "5.4.1",
                  "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/Alamofire",
                  "dependencies": [

                  ]
                },
                {
                  "name": "ReactiveSwift",
                  "url": "https://github.com/Moya/ReactiveSwift.git",
                  "version": "6.1.0",
                  "path": "/Users/kamilharasimowicz/Documents/Projects/SPM_tests/.build/checkouts/ReactiveSwift",
                  "dependencies": [

                  ]
                }
              ]
            }
          ]
        }
        """
        
        let command = [
            "swift",
            "package",
            "--package-path",
            path.pathString,
            "show-dependencies",
            "--format",
            "json",
        ]
        system.succeedCommand(command, output: json)
        
        // When
        let got = try subject.loadDepedencies(at: path)
        
        // Then
        XCTAssertCodableEqualToJson(got, json)
    }
}
