import Foundation
import Testing

@MainActor
struct AtlasTimeOffTests {
    private let overview = Data("""
    {"requests":{"items":[{"id":"request","starts_on":"2027-06-07","ends_on":"2027-06-11",
    "status":"pending","working_days":5,"missing_years":[]}],"page":1,"total_pages":2,"total_count":11},
    "public_holidays":{"items":[{"id":"holiday","name":"Public holiday","date":"2027-12-25"}],
    "page":1,"total_pages":1,"total_count":1}}
    """.utf8)

    @Test func loadsPersonalHistoryAndPublicHolidaysWithIndependentPages() async {
        let model = AtlasTimeOff { action in
            #expect(action["action"] as? String == "list")
            #expect(action["requests_page"] as? Int == 2)
            #expect(action["holidays_page"] as? Int == 3)
            return overview
        }
        await model.load(requestsPage: 2, holidaysPage: 3)
        #expect(model.overview?.requests.items.first?.workingDays == 5)
        #expect(model.overview?.publicHolidays.items.first?.name == "Public holiday")
        #expect(model.errorMessage == nil && !model.busy)
    }

    @Test func createsEditsAndCancelsUsingOnlyDatesAndRequestIDs() async throws {
        var actions: [String] = []
        let model = AtlasTimeOff { action in
            let operation = action["action"] as? String ?? ""
            actions.append(operation)
            if operation == "create" || operation == "update" {
                #expect(action["starts_on"] as? String == "2027-06-07")
                #expect(action["ends_on"] as? String == "2027-06-11")
                #expect(action["user_id"] == nil && action["status"] == nil)
            }
            if operation == "update" || operation == "cancel" { #expect(action["id"] as? String == "request") }
            return operation == "list" ? overview : Data("{}".utf8)
        }
        #expect(await model.save(startsOn: "2027-06-07", endsOn: "2027-06-11", editing: nil))
        let booking = try #require(model.overview?.requests.items.first)
        #expect(await model.save(startsOn: "2027-06-07", endsOn: "2027-06-11", editing: booking))
        await model.cancel(booking)
        #expect(actions == ["create", "list", "update", "list", "cancel", "list"])
    }

    @Test func failedSaveKeepsHistoryAndSuccessfulMutationDoesNotBecomeAFailedSaveWhenReloadFails() async {
        var failMutation = true
        let model = AtlasTimeOff { action in
            if action["action"] as? String == "create" && !failMutation { return Data("{}".utf8) }
            throw AtlasAuthenticationError(kind: "server", message: "Try again")
        }
        #expect(!(await model.save(startsOn: "2027-06-07", endsOn: "2027-06-11", editing: nil)))
        #expect(model.errorMessage == "Try again")
        failMutation = false
        #expect(await model.save(startsOn: "2027-06-07", endsOn: "2027-06-11", editing: nil))
        #expect(model.errorMessage == "Try again" && !model.busy)
    }

    @Test func ordinaryFailuresRetainPreviouslyLoadedHistory() async throws {
        var shouldFail = false
        let model = AtlasTimeOff { _ in
            if shouldFail { throw AtlasAuthenticationError(kind: "server", message: "Try again") }
            return overview
        }
        await model.load()
        let original = try #require(model.overview?.requests.items.first)
        shouldFail = true
        await model.load(requestsPage: 2)
        #expect(model.overview?.requests.items.first?.id == original.id && model.errorMessage == "Try again")
        #expect(!(await model.save(startsOn: "2027-06-07", endsOn: "2027-06-11", editing: original)))
        #expect(model.overview?.requests.items.first?.id == original.id && !model.busy)
    }

    @Test func cancelledRequestsCannotBeEditedAndOnlyActiveRequestsCanBeCancelled() async {
        let model = AtlasTimeOff { _ in Issue.record("Unexpected request"); return Data() }
        for status in ["cancelled", "rejected"] {
            let booking = AtlasHolidayRequest(id: "request", startsOn: "2027-06-07", endsOn: "2027-06-11",
                                             status: status, workingDays: 5, missingYears: [])
            await model.cancel(booking)
            if status == "cancelled" {
                #expect(!(await model.save(startsOn: booking.startsOn, endsOn: booking.endsOn, editing: booking)))
            }
        }
        #expect(!model.busy)
        #expect(AtlasHolidayDates.encode(AtlasHolidayDates.bounds.lowerBound) == "2000-01-01")
        #expect(AtlasHolidayDates.encode(AtlasHolidayDates.bounds.upperBound) == "2100-12-31")
    }

    @Test func inFlightSaveRejectsDoubleSubmission() async {
        let started = AsyncStream<Void>.makeStream()
        var finish: CheckedContinuation<Data, Never>?
        var creates = 0
        let model = AtlasTimeOff { action in
            if action["action"] as? String == "create" {
                creates += 1
                return await withCheckedContinuation { finish = $0; started.continuation.yield(()) }
            }
            return overview
        }
        let save = Task { await model.save(startsOn: "2027-06-07", endsOn: "2027-06-11", editing: nil) }
        for await _ in started.stream { break }
        #expect(!(await model.save(startsOn: "2027-06-07", endsOn: "2027-06-11", editing: nil)))
        finish?.resume(returning: Data("{}".utf8))
        #expect(await save.value)
        #expect(creates == 1)
    }

    @Test(arguments: ["2027-06-07", "2027-06-11", "2028-02-29", "2027-03-28", "2027-10-31"])
    func calendarDatesRoundTripWithoutAnInstantConversion(value: String) throws {
        let date = try #require(AtlasHolidayDates.decode(value))
        #expect(AtlasHolidayDates.encode(date) == value)
    }
}
