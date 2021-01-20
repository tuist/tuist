import Foundation
import RxBlocking
import RxSwift
import TuistCore
import XCTest
import TuistGraph

@testable import TuistCache
@testable import TuistCacheTesting
@testable import TuistCoreTesting
@testable import TuistSupportTesting

final class CacheBuildPhaseProjectMapperTests: TuistUnitTestCase {
    var subject: CacheBuildPhaseProjectMapper!

    override func setUp() {
        subject = CacheBuildPhaseProjectMapper()
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_map_when_the_target_is_a_framework() throws {
        // When
        let target = Target.test(product: .framework, productName: "Framework")
        let project = Project.test(targets: [target])

        // When
        let (got, _) = try subject.map(project: project)

        // Then
        let script = try XCTUnwrap(got.targets.first?.scripts.first)
        XCTAssertEqual(script.name, "[Tuist] Create file to locate the built products directory")
        let expected = """
        if [ -n "$\(target.targetLocatorBuildPhaseVariable)" ]; then
            touch $BUILT_PRODUCTS_DIR/.$\(target.targetLocatorBuildPhaseVariable).tuist
        fi
        """
        XCTAssertEqual(script.script, expected)
        XCTAssertTrue(script.showEnvVarsInLog)
    }

    func test_map_when_the_target_is_not_a_framework() throws {
        // When
        let target = Target.test(product: .app, productName: "App")
        let project = Project.test(targets: [target])

        // When
        let (got, _) = try subject.map(project: project)

        // Then
        XCTAssertEqual(got.targets.first?.scripts.count, 0)
    }
}
