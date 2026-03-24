import Foundation
import Testing
import TuistAutomation
import TuistLoader
@testable import TuistCore
@testable import TuistGenerator
@testable import TuistKit
@testable import TuistTesting

struct ProjectMapperFactoryTests {
    var subject: ProjectMapperFactory!

    init() {
        subject = ProjectMapperFactory()
    }

    @Test func default_when_synthesizing_of_resource_interfaces_is_disabled() {
        // When
        let got = subject.default(tuist: .default)

        // Then

        XCTAssertContainsElementOfType(got, SynthesizedResourceInterfaceProjectMapper.self)
    }

    @Test func default_contains_target_mapper() {
        // When
        let got = subject.default(tuist: .default)

        // Then

        XCTAssertContainsElementOfType(got, TargetActionDisableShowEnvVarsProjectMapper.self)
    }

    @Test func default_when_bundle_accessors_are_enabled() {
        // When
        let got = subject.default(tuist: .default)

        // Then

        XCTAssertContainsElementOfType(got, ResourcesProjectMapper.self)
        XCTAssertContainsElementOfType(got, ResourcesProjectMapper.self, after: DeleteDerivedDirectoryProjectMapper.self)
    }

    @Test func default_contains_the_generate_info_plist_mapper() {
        // When
        let got = subject.default(tuist: .default)

        // Then
        XCTAssertContainsElementOfType(got, GenerateInfoPlistProjectMapper.self, after: DeleteDerivedDirectoryProjectMapper.self)
    }

    @Test func default_contains_the_generate_privacy_manifest_mapper() {
        // When
        let got = subject.default(tuist: .default)

        // Then
        XCTAssertContainsElementOfType(
            got,
            GeneratePrivacyManifestProjectMapper.self,
            after: DeleteDerivedDirectoryProjectMapper.self
        )
    }

    @Test func default_contains_the_ide_template_macros_mapper() {
        // When
        let got = subject.default(tuist: .default)

        // Then
        XCTAssertContainsElementOfType(got, IDETemplateMacrosMapper.self)
    }

    @Test func automation_contains_the_skip_ui_tests_mapper_when_skip_ui_tests_is_true() {
        // When
        let got = subject.automation(
            skipUITests: true,
            skipUnitTests: false,
            tuist: .default
        )

        // Then
        XCTAssertContainsElementOfType(got, SkipUITestsProjectMapper.self)
    }

    @Test func automation_doesnt_contain_the_skip_ui_tests_mapper_when_skip_ui_tests_is_false() {
        // When
        let got = subject.automation(
            skipUITests: false,
            skipUnitTests: false,
            tuist: .default
        )

        // Then
        XCTAssertDoesntContainElementOfType(got, SkipUITestsProjectMapper.self)
    }

    @Test func automation_contains_the_skip_unit_tests_mapper_when_skip_unit_tests_is_true() {
        // When
        let got = subject.automation(
            skipUITests: false,
            skipUnitTests: true,
            tuist: .default
        )

        // Then
        XCTAssertContainsElementOfType(got, SkipUnitTestsProjectMapper.self)
    }

    @Test func automation_doesnt_contain_the_skip_unit_tests_mapper_when_skip_unit_tests_is_false() {
        // When
        let got = subject.automation(
            skipUITests: false,
            skipUnitTests: false,
            tuist: .default
        )

        // Then
        XCTAssertDoesntContainElementOfType(got, SkipUnitTestsProjectMapper.self)
    }
}
