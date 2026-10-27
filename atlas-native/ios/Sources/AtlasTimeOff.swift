import Foundation
import SwiftUI

struct AtlasHolidayRequest: Decodable, Identifiable {
    let id: String
    let startsOn: String
    let endsOn: String
    let status: String
    let workingDays: Int?
    let missingYears: [Int]
    var canEdit: Bool { status != "cancelled" }
    var canCancel: Bool { status == "pending" || status == "approved" }
}

struct AtlasPublicHoliday: Decodable, Identifiable {
    let id: String
    let name: String
    let date: String
}

struct AtlasHolidayPage<Item: Decodable>: Decodable {
    let items: [Item]
    let page: Int
    let totalPages: Int
    let totalCount: Int
}

struct AtlasHolidayOverview: Decodable {
    let requests: AtlasHolidayPage<AtlasHolidayRequest>
    let publicHolidays: AtlasHolidayPage<AtlasPublicHoliday>
}

enum AtlasHolidayDates {
    static var calendar: Calendar { Calendar(identifier: .gregorian) }
    static var bounds: ClosedRange<Date> {
        (decode("2000-01-01") ?? .distantPast)...(decode("2100-12-31") ?? .distantFuture)
    }

    private static var formatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }

    static func encode(_ date: Date) -> String { formatter.string(from: date) }
    static func decode(_ value: String) -> Date? { formatter.date(from: value) }
}

@MainActor
final class AtlasTimeOff: ObservableObject {
    @Published private(set) var overview: AtlasHolidayOverview?
    @Published private(set) var busy = false
    @Published private(set) var mutating = false
    @Published var errorMessage: String?
    private let request: ([String: Any]) async throws -> Data

    init(request: @escaping ([String: Any]) async throws -> Data) { self.request = request }

    func load(requestsPage: Int = 1, holidaysPage: Int = 1) async {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        defer { busy = false }
        do {
            try await fetch(requestsPage: requestsPage, holidaysPage: holidaysPage)
        } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
    }

    func save(startsOn: String, endsOn: String, editing: AtlasHolidayRequest?) async -> Bool {
        guard editing?.canEdit != false else { return false }
        var action: [String: Any] = ["action": editing == nil ? "create" : "update", "starts_on": startsOn, "ends_on": endsOn]
        if let editing { action["id"] = editing.id }
        return await mutate(action)
    }

    func cancel(_ booking: AtlasHolidayRequest) async {
        guard booking.canCancel else { return }
        _ = await mutate(["action": "cancel", "id": booking.id])
    }

    private func mutate(_ action: [String: Any]) async -> Bool {
        guard !busy else { return false }
        busy = true
        mutating = true
        errorMessage = nil
        defer { busy = false; mutating = false }
        do {
            _ = try await request(action)
        } catch is CancellationError { return false } catch {
            errorMessage = error.localizedDescription
            return false
        }
        // The mutation succeeded even if reloading fails. Do not invite duplicate submissions.
        do {
            try await fetch(requestsPage: 1, holidaysPage: overview?.publicHolidays.page ?? 1)
        } catch is CancellationError {} catch { errorMessage = error.localizedDescription }
        return true
    }

    private func fetch(requestsPage: Int, holidaysPage: Int) async throws {
        let data = try await request(["action": "list", "requests_page": requestsPage, "holidays_page": holidaysPage])
        try Task.checkCancellation()
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        overview = try decoder.decode(AtlasHolidayOverview.self, from: data)
    }
}
