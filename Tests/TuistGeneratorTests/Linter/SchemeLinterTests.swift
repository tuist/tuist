
import Foundation
import TuistSupport
import XCTest
@testable import TuistGenerator

class SchemeLinterTests: XCTestCase {
    var subject: SchemeLinter!

    override func setUp() {
        super.setUp()
        subject = SchemeLinter()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_lint_missingConfigurations() {
        // Given
        let settings = Settings(configurations: [
            .release("Beta"): .test(),
        ])
        let scheme = Scheme(name: "CustomScheme",
                            testAction: .test(configurationName: "Alpha"),
                            runAction: .test(configurationName: "CustomDebug"))
        let project = Project.test(settings: settings, schemes: [scheme])

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got.first?.severity, .error)
        XCTAssertEqual(got.last?.severity, .error)
        XCTAssertEqual(got.first?.reason, "The build configuration 'CustomDebug' specified in the scheme's run action isn't defined in the project.")
        XCTAssertEqual(got.last?.reason, "The build configuration 'Alpha' specified in the scheme's test action isn't defined in the project.")
    }
}
