import ArgumentParser
import Foundation
import Testing
@testable import TuistRunnerCommand

struct RunnerVolumeCommandTests {
    private let id = "a57a427c-1ffc-476f-9282-558ff3f61585"

    @Test func parsesPaginatedFilters() throws {
        let command = try RunnerVolumeListCommand.parse([
            "--account",
            "acme",
            "--name",
            "gradle",
            "--repository",
            "acme/android",
            "--page",
            "2",
            "--page-size",
            "5",
            "--sort-by",
            "used_space",
            "--sort-order",
            "asc",
            "--json",
        ])
        #expect(command.options.account == "acme")
        #expect(command.name == "gradle")
        #expect(command.repository == "acme/android")
        #expect(command.pagination.page == 2)
        #expect(command.pagination.pageSize == 5)
        #expect(command.sortBy == .usedSpace)
        #expect(command.sortOrder == .asc)
        #expect(command.options.json)
    }

    @Test func accountIsOptionalAndSearchIsNotAccepted() throws {
        let command = try RunnerVolumeListCommand.parse(["--name", "gradle"])
        #expect(command.options.account == nil)
        #expect(throws: (any Error).self) { try RunnerVolumeListCommand.parse(["--search", "gradle"]) }
    }

    @Test func rejectsUnboundedPages() {
        #expect(throws: (any Error).self) { try RunnerVolumeListCommand.parse(["--page-size", "101"]) }
        #expect(throws: (any Error).self) { try RunnerVolumeListCommand.parse(["--page", "0"]) }
    }

    @Test func clearingRequiresExplicitConfirmationAndValidID() throws {
        #expect(throws: (any Error).self) { try RunnerVolumeClearCommand.parse([id]) }
        #expect(throws: (any Error).self) { try RunnerVolumeClearCommand.parse(["invalid", "--yes"]) }
        let command = try RunnerVolumeClearCommand.parse([id, "--yes", "--account", "acme"])
        #expect(command.volumeID == id)
        #expect(command.yes)
    }

    @Test func validatesAnalyticsRange() throws {
        let command = try RunnerVolumeAnalyticsCommand.parse([
            "--volume",
            id,
            "--start",
            "2026-01-01T00:00:00.000Z",
            "--end",
            "2026-01-02T00:00:00Z",
        ])
        let (start, end) = try command.dateRange()
        #expect(try #require(end).timeIntervalSince(#require(start)) == 86400)
        #expect(throws: (any Error).self) { try RunnerVolumeAnalyticsCommand.parse([
            "--start",
            "2026-01-03T00:00:00Z",
            "--end",
            "2026-01-02T00:00:00Z",
        ]) }
        #expect(throws: (any Error).self) { try RunnerVolumeAnalyticsCommand.parse(["--start", "yesterday"]) }
    }

    @Test func rejectsInvalidJobID() {
        #expect(throws: (any Error).self) { try RunnerVolumeForJobCommand.parse(["0"]) }
    }
}
