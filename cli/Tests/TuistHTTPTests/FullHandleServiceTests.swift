import Foundation
import Testing

@testable import TuistHTTP

struct FullHandleServiceTests {
    private let subject: FullHandleServicing

    init() {
        subject = FullHandleService()
    }

    @Test func parsing_full_handle_when_valid() throws {
        // When
        let got = try subject.parse("tuist-org/tuist")

        // Then
        #expect(got.accountHandle == "tuist-org")
        #expect(got.projectHandle == "tuist")
    }

    @Test func parsing_full_handle_when_only_account_or_project_handle_is_present() throws {
        // When / Then
        #expect(throws: FullHandleServiceError.invalidHandle("tuist")) {
            try subject.parse("tuist")
        }
    }

    @Test func parsing_full_handle_when_extra_components_are_present() throws {
        // When / Then
        #expect(throws: FullHandleServiceError.invalidHandle("tuist-org/tuist/extra")) {
            try subject.parse("tuist-org/tuist/extra")
        }
    }
}
