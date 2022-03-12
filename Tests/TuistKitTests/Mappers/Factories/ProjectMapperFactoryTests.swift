import Foundation
import TSCBasic
import TuistAutomation
import TuistCoreTesting
import TuistGraph
import TuistLoader
import TuistSigning
import XCTest
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistKit
@testable import TuistSupportTesting

final class ProjectMapperFactoryTests: TuistUnitTestCase {
    var subject: ProjectMapperFactory!

    override func setUp() {
        super.setUp()
        subject = ProjectMapperFactory()
    }

    override func tearDown() {
        subject = nil
        super.tearDown()
    }

    func test_default_when_synthesizing_of_resource_interfaces_is_disabled() {
        // When
        let got = subject.default()

        // Then

        XCTAssertContainsElementOfType(got, SynthesizedResourceInterfaceProjectMapper.self)
    }

    func test_default_contains_target_mapper() {
        // When
        let got = subject.default()

        // Then

        XCTAssertContainsElementOfType(got, TargetActionDisableShowEnvVarsProjectMapper.self)
    }

    func test_default_when_bundle_accessors_are_enabled() {
        // When
        let got = subject.default()

        // Then

        XCTAssertContainsElementOfType(got, ResourcesProjectMapper.self)
        XCTAssertContainsElementOfType(got, ResourcesProjectMapper.self, after: DeleteDerivedDirectoryProjectMapper.self)
    }

    func test_default_contains_the_generate_info_plist_mapper() {
        // When
        let got = subject.default()

        // Then
        XCTAssertContainsElementOfType(got, GenerateInfoPlistProjectMapper.self, after: DeleteDerivedDirectoryProjectMapper.self)
    }

    func test_default_contains_the_ide_template_macros_mapper() {
        // When
        let got = subject.default()

        // Then
        XCTAssertContainsElementOfType(got, IDETemplateMacrosMapper.self)
    }

    func test_default_contains_the_signing_mapper() {
        // When
        let got = subject.default()

        // Then
        XCTAssertContainsElementOfType(got, SigningMapper.self)
    }

    func test_automation_contains_the_source_root_path_project_mapper() {
        // When
        let got = subject.automation(skipUITests: true)

        // Then
        XCTAssertContainsElementOfType(got, SourceRootPathProjectMapper.self)
    }

    func test_automation_contains_the_skip_ui_tests_mapper_when_skip_ui_tests_is_true() {
        // When
        let got = subject.automation(skipUITests: true)

        // Then
        XCTAssertContainsElementOfType(got, SkipUITestsProjectMapper.self)
    }

    func test_automation_doesnt_contain_the_skip_ui_tests_mapper_when_skip_ui_tests_is_false() {
        // When
        let got = subject.automation(skipUITests: false)

        // Then
        XCTAssertDoesntContainElementOfType(got, SkipUITestsProjectMapper.self)
    }
}
