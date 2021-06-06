import TSCBasic
import TSCUtility
import TuistCore
import TuistGraph
import TuistSupport
import XCTest

@testable import TuistDependencies
@testable import TuistDependenciesTesting
@testable import TuistSupportTesting

final class CarthageGraphGeneratorTests: TuistUnitTestCase {
    private var subject: CarthageGraphGenerator!
    
    override func setUp() {
        super.setUp()
        
        subject = CarthageGraphGenerator()
    }
    
    override func tearDown() {
        super.tearDown()
        
        subject = nil
    }
    
    func test_generate() throws {
        // Given
        let path = try temporaryPath()
        
        let rxSwiftVersionFilePath = path.appending(component: ".RxSwift.version")
        try fileHandler.touch(rxSwiftVersionFilePath)
        try fileHandler.write(CarthageVersionFile.testRxSwiftJson, path: rxSwiftVersionFilePath, atomically: true)
        
        let alamofireVersionFilePath = path.appending(component: ".Alamofire.version")
        try fileHandler.touch(alamofireVersionFilePath)
        try fileHandler.write(CarthageVersionFile.testAlamofireJson, path: alamofireVersionFilePath, atomically: true)
        
        // When
        let got = try subject.generate(at: path)
        
        // Then
        let expected = DependenciesGraph(
            thirdPartyDependencies: [
                "RxSwift" : .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxSwift.xcframework",
                    architectures: [.armv7k, .arm64, .i386, .x8664, .armv7, .arm6432]
                ),
                "RxCocoa" : .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxCocoa.xcframework",
                    architectures: [.armv7, .armv7k, .arm6432, .x8664, .i386, .arm64]
                ),
                "RxRelay" : .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxRelay.xcframework",
                    architectures: [.armv7k, .i386, .x8664, .armv7, .arm6432, .arm64]
                ),
                "RxTest" : .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxTest.xcframework",
                    architectures: [.i386, .x8664, .arm64, .armv7]
                ),
                "RxBlocking" : .xcframework(
                    path: "/Tuist/Dependencies/Carthage/RxBlocking.xcframework",
                    architectures: [.arm64, .armv7k, .x8664, .arm6432, .i386, .armv7]
                ),
                "Alamofire" : .xcframework(
                    path: "/Tuist/Dependencies/Carthage/Alamofire.xcframework",
                    architectures: [.x8664, .armv7k, .i386, .arm64, .armv7, .arm6432]
                ),
            ]
        )
        
        XCTAssertEqual(got, expected)
    }
}
