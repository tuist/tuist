import Foundation
import OpenAPIRuntime
import Testing

@testable import TuistServer

struct ExpectCommitCoverageRunsServiceTests {
    @Test func acceptsTheRegistration() throws {
        try ExpectCommitCoverageRunsService.validate(.noContent(.init()))
    }

    @Test func carriesTheServersMessageOnAClientError() {
        #expect(throws: ExpectCommitCoverageRunsServiceError.notFound("Project not found")) {
            try ExpectCommitCoverageRunsService.validate(.notFound(.init(body: .json(.init(message: "Project not found")))))
        }
        #expect(throws: ExpectCommitCoverageRunsServiceError.forbidden("Not allowed")) {
            try ExpectCommitCoverageRunsService.validate(.forbidden(.init(body: .json(.init(message: "Not allowed")))))
        }
        #expect(throws: ExpectCommitCoverageRunsServiceError.unauthorized("Sign in")) {
            try ExpectCommitCoverageRunsService.validate(.unauthorized(.init(body: .json(.init(message: "Sign in")))))
        }
    }

    @Test func reportsAnUndocumentedStatus() {
        #expect(throws: ExpectCommitCoverageRunsServiceError.unknownError(500)) {
            try ExpectCommitCoverageRunsService.validate(.undocumented(statusCode: 500, .init()))
        }
    }
}
