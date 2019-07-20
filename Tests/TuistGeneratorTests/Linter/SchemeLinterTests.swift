
import Foundation
import TuistCore
import XCTest
@testable import TuistGenerator

class SchemeLinterTests: XCTestCase {
    var subject: SchemeLinter!

    override func setUp() {
        super.setUp()
        subject = SchemeLinter()
    }

    func test_lint_missingConfigurations() {
        // Given
        let settings = Settings(configurations: [
            .release("Beta"): .test(),
        ])
        let scheme = Scheme(name: "CustomScheme",
                            testAction: .test(config: .release("Alpha")),
                            runAction: .test(config: .debug("CustomDebug")))
        let project = Project.test(settings: settings, schemes: [scheme])

        // When
        let got = subject.lint(project: project)

        // Then
        XCTAssertEqual(got.map { $0.severity }, [.error, .error])
        XCTAssertEqual(got.map { $0.reason }, [
            "The debug configuration 'CustomDebug' specified in the scheme's run action isn't defined in the project.",
            "The release configuration 'Alpha' specified in the scheme's test action isn't defined in the project.",
        ])
    }
}
