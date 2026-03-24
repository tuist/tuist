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

        #expect(got.contains(where: { $0 is SynthesizedResourceInterfaceProjectMapper }))
    }

    @Test func default_contains_target_mapper() {
        // When
        let got = subject.default(tuist: .default)

        // Then

        #expect(got.contains(where: { $0 is TargetActionDisableShowEnvVarsProjectMapper }))
    }

    @Test func default_when_bundle_accessors_are_enabled() {
        // When
        let got = subject.default(tuist: .default)

        // Then

        #expect(got.contains(where: { $0 is ResourcesProjectMapper }))
        if let elementIndex = got.lastIndex(where: { $0 is ResourcesProjectMapper }),
           let previousIndex = got.firstIndex(where: { $0 is DeleteDerivedDirectoryProjectMapper })
        {
            #expect(elementIndex > previousIndex)
        } else {
            Issue.record("Expected element of type ResourcesProjectMapper after DeleteDerivedDirectoryProjectMapper")
        }
    }

    @Test func default_contains_the_generate_info_plist_mapper() {
        // When
        let got = subject.default(tuist: .default)

        // Then
        if let elementIndex = got.lastIndex(where: { $0 is GenerateInfoPlistProjectMapper }),
           let previousIndex = got.firstIndex(where: { $0 is DeleteDerivedDirectoryProjectMapper })
        {
            #expect(elementIndex > previousIndex)
        } else {
            Issue.record("Expected element of type GenerateInfoPlistProjectMapper after DeleteDerivedDirectoryProjectMapper")
        }
    }

    @Test func default_contains_the_generate_privacy_manifest_mapper() {
        // When
        let got = subject.default(tuist: .default)

        // Then
        if let elementIndex = got.lastIndex(where: { $0 is GeneratePrivacyManifestProjectMapper }),
           let previousIndex = got.firstIndex(where: { $0 is DeleteDerivedDirectoryProjectMapper })
        {
            #expect(elementIndex > previousIndex)
        } else {
            Issue
                .record("Expected element of type GeneratePrivacyManifestProjectMapper after DeleteDerivedDirectoryProjectMapper")
        }
    }

    @Test func default_contains_the_ide_template_macros_mapper() {
        // When
        let got = subject.default(tuist: .default)

        // Then
        #expect(got.contains(where: { $0 is IDETemplateMacrosMapper }))
    }

    @Test func automation_contains_the_skip_ui_tests_mapper_when_skip_ui_tests_is_true() {
        // When
        let got = subject.automation(
            skipUITests: true,
            skipUnitTests: false,
            tuist: .default
        )

        // Then
        #expect(got.contains(where: { $0 is SkipUITestsProjectMapper }))
    }

    @Test func automation_doesnt_contain_the_skip_ui_tests_mapper_when_skip_ui_tests_is_false() {
        // When
        let got = subject.automation(
            skipUITests: false,
            skipUnitTests: false,
            tuist: .default
        )

        // Then
        #expect(!got.contains(where: { $0 is SkipUITestsProjectMapper }))
    }

    @Test func automation_contains_the_skip_unit_tests_mapper_when_skip_unit_tests_is_true() {
        // When
        let got = subject.automation(
            skipUITests: false,
            skipUnitTests: true,
            tuist: .default
        )

        // Then
        #expect(got.contains(where: { $0 is SkipUnitTestsProjectMapper }))
    }

    @Test func automation_doesnt_contain_the_skip_unit_tests_mapper_when_skip_unit_tests_is_false() {
        // When
        let got = subject.automation(
            skipUITests: false,
            skipUnitTests: false,
            tuist: .default
        )

        // Then
        #expect(!got.contains(where: { $0 is SkipUnitTestsProjectMapper }))
    }
}
