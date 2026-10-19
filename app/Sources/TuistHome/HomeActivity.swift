import Foundation

public enum HomeActivityKind: String, CaseIterable, Hashable, Sendable {
    case buildFailures
    case testFailures
    case flakyTests

    public var title: String {
        switch self {
        case .buildFailures: "Build failures"
        case .testFailures: "Test failures"
        case .flakyTests: "New flaky tests"
        }
    }

    public var emptyMessage: String {
        switch self {
        case .buildFailures: "No failed builds reported in the last seven days."
        case .testFailures: "No failed test runs reported in the last seven days."
        case .flakyTests: "No tests newly marked flaky in the last seven days."
        }
    }

    var symbol: String { self == .flakyTests ? "exclamationmark.triangle" : "xmark.circle" }
}

public struct HomeActivityItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let occurredAt: Date
    public let url: URL

    public init(id: String, title: String, subtitle: String, occurredAt: Date, url: URL) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.occurredAt = occurredAt
        self.url = url
    }
}

public struct HomeActivitySection: Equatable, Sendable {
    public var items: [HomeActivityItem] = []
    public var isLoading = false
    public var hasLoaded = false
    public var errorMessage: String?
}
