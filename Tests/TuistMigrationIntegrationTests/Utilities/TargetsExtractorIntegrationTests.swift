import Foundation
import TSCBasic
import TuistSupport
import XCTest

@testable import TuistMigration
@testable import TuistSupportTesting

final class TargetsExtractorIntegrationTests: TuistTestCase {
    var subject: TargetsExtractor!

    override func setUp() {
        super.setUp()
        subject = TargetsExtractor()
    }

    override func tearDown() {
        super.tearDown()
        subject = nil
    }

    func test_whenXcodeProjectDoesntExist_throwsExpectedError() throws {
        // Given
        let xcodeprojPath = AbsolutePath("/invalid/path.xcodeproj")

        // Then
        XCTAssertThrowsSpecific(try subject.targetsSortedByDependencies(
            xcodeprojPath: xcodeprojPath), TargetsExtractorError.missingXcodeProj(xcodeprojPath))
    }

    func test_whenProjectIsFrameworksFixture_returnsExpectedFrameworks() throws {
        // Given
        let xcodeprojPath = fixturePath(path: RelativePath("Frameworks/Frameworks.xcodeproj"))

        // When
        let targets = try subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)

        let targetNames = targets.map { $0.targetName }
        let depsCount = targets.map { $0.dependenciesCount }

        XCTAssertEqual(targetNames, ["iOS", "macOS", "tvOS", "watchOS"])
        XCTAssertEqual(depsCount, [0, 0, 0, 0])
    }

    func test_whenProjectIsMicrofeaturesFixtureApp_returnsExpectedFrameworks() throws {
        // Given
        let xcodeprojPath = fixturePath(path: RelativePath("ios_workspace_with_microfeature_architecture/App/App.xcodeproj"))

        // When
        let targets = try subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)

        let targetNames = targets.map { $0.targetName }
        let depsCount = targets.map { $0.dependenciesCount }

        XCTAssertEqual(targetNames, ["App", "AppTests"])
        XCTAssertEqual(depsCount, [1, 1])
    }

    func test_whenProjectIsMicrofeaturesFixtureUIComponents_returnsExpectedFrameworks() throws {
        // Given
        let xcodeprojPath = fixturePath(path: RelativePath("ios_workspace_with_microfeature_architecture/Frameworks/UIComponentsFramework/UIComponents.xcodeproj"))

        // When
        let targets = try subject.targetsSortedByDependencies(xcodeprojPath: xcodeprojPath)

        let targetNames = targets.map { $0.targetName }
        let depsCount = targets.map { $0.dependenciesCount }

        XCTAssertEqual(targetNames, ["UIComponents", "UIComponentsTests"])
        XCTAssertEqual(depsCount, [1, 2])
    }
}
