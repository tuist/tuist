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

    @Test func removedForJobCommandIsRejected() {
        #expect(throws: (any Error).self) { try RunnerVolumeCommand.parseAsRoot(["for-job", "1024"]) }
    }

    @Test func formatsVolumeSizesAndPreservesUnknownMeasurements() throws {
        let volume = try decode(RunnerVolumeService.VolumeList.volumesPayloadPayload.self, volumeJSON)
        let row = RunnerVolumeService.volumeRow(volume)
        #expect(row[1] == "gradle-dependencies")
        #expect(row[3] == "Linux · amd64")
        #expect(row[4].replacingOccurrences(of: ",", with: ".").contains("2.7 GB"))
        #expect(row[5].contains("20 GB"))
        #expect(RunnerVolumeService.bytes(nil) == "Not reported")
        #expect(RunnerVolumeService.bytes(0) != "Not reported")
        #expect(RunnerVolumeService.bytes(2_700_000_000, unmeasured: 1).hasSuffix("(partial)"))
    }

    @Test func formatsCacheOutcomesWithoutConfusingUnknownWithMiss() throws {
        var job = try decode(RunnerVolumeService.VolumeJobs.jobsPayloadPayload.self, """
        {"id":"use-id","workflow_job_id":1024,"workflow_run_id":500,
         "job_name":"Build and test","workflow_name":"CI","cache_status":"saved",
         "cache_status_description":"Changes saved for future runs.","cache_hit":true,
         "used_bytes":2700000000}
        """)
        #expect(RunnerVolumeService.jobRow(job)[1 ... 4] == ["Build and test", "CI", "Saved", "Hit"])
        job.cache_hit = false
        #expect(RunnerVolumeService.jobRow(job)[4] == "Miss")
        job.cache_hit = nil
        #expect(RunnerVolumeService.jobRow(job)[4] == "Not reported")
        #expect(RunnerVolumeService.jobRow(job).last == "Not mounted")
    }

    @Test func detailsUseReadableLabelsAndUnits() throws {
        let volume = try decode(RunnerVolumeService.VolumeDetails.self, volumeJSON)
        let text = RunnerVolumeService.details(volume)
        #expect(text.contains("Name: gradle-dependencies"))
        #expect(text.contains("Provider: GitHub"))
        #expect(text.contains("Capacity: 20 GB"))
        #expect(!text.contains("capacity_bytes"))
        #expect(!text.contains("20000000000"))
    }

    @Test func analyticsSummarizesActivityAndTrends() throws {
        let analytics = try decode(RunnerVolumeService.VolumeAnalytics.self, """
        {"period":{"start":"2026-01-01T00:00:00Z","end":"2026-01-02T00:00:00Z"},
         "activity":{"hit_rate":95.8,"job_runs":24,"points":[]},
         "previous_activity":{"hit_rate":90,"job_runs":20,"points":[]},
         "storage":[{"at":"2026-01-02T00:00:00Z","volumes":1,"used_bytes":2700000000,
                     "unmeasured_copies":1,"unmeasured_capacity_copies":0}],
         "trends":{"hit_rate_percentage_points":5.8,"used_bytes":{"change":700000000,"percent":35},
                   "volumes":{"change":0,"percent":0}}}
        """)
        let text = RunnerVolumeService.analyticsSummary(analytics)
        #expect(text.contains("Job runs: 24"))
        #expect(text.contains("(partial)"))
        #expect(text.contains("Cache hit rate: 95.8%"))
        #expect(text.contains("Hit rate change: +5.8 percentage points"))
        #expect(text.contains("Used space change: +35.0%"))
        #expect(RunnerVolumeService.percentage(nil) == "Not available")
        #expect(RunnerVolumeService.percentage(0) == "0.0%")
        #expect(!text.contains("points:"))
    }

    private var volumeJSON: String {
        """
        {"id":"\(id)","key":"gradle-dependencies","repository":"demo/android-app",
         "provider":"github","platform":"linux","architecture":"amd64",
         "used_bytes":2700000000,"capacity_bytes":20000000000,
         "unmeasured_copies":0,"unmeasured_capacity_copies":0}
        """
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(json.utf8))
    }
}
