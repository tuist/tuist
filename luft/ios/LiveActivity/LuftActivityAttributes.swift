import ActivityKit
import Foundation

/// The ActivityKit contract shared by the app and the widget extension.
///
/// The server decides what the activity shows (`Tuist.Push.LiveActivities` in
/// the server): `ContentState` is its versioned document, which APNs delivers
/// as the activity's `content-state` and the widget only draws. Its fields use
/// the server's snake-case names, decoded with Apple's default JSON strategy.
/// Decoding is lenient so a newer server's document still draws: missing
/// fields fall back, and a version past `supportedVersion` shows its
/// `fallback` text instead of parts this app doesn't know.
// swiftlint:disable nesting
struct LuftActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        static let supportedVersion = 1

        struct Summary: Codable, Hashable {
            var headline: String
            var phase: String
            var symbol: String
            var tint: String

            init(headline: String, phase: String, symbol: String, tint: String) {
                self.headline = headline
                self.phase = phase
                self.symbol = symbol
                self.tint = tint
            }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                headline = try values.decodeIfPresent(String.self, forKey: .headline) ?? ""
                phase = try values.decodeIfPresent(String.self, forKey: .phase) ?? ""
                symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? "sparkles"
                tint = try values.decodeIfPresent(String.self, forKey: .tint) ?? "gray"
            }
        }

        struct Progress: Codable, Hashable {
            /// `timer`, counted on the device from `started_at`, or `steps`. A
            /// build's timer also carries `done` of `total` planned targets.
            var kind: String
            var startedAt: TimeInterval?
            var done: Int?
            var total: Int?

            enum CodingKeys: String, CodingKey {
                case kind, done, total
                case startedAt = "started_at"
            }
        }

        struct Thread: Codable, Hashable, Identifiable {
            var id: String
            var headline: String
            var detail: String
            /// `waiting`, `thinking`, `exploring`, `editing`, `running`, `working`,
            /// `shipping`, `needs_you`, `done` or `failed`, decided by the server.
            var phase: String
            var symbol: String
            var tint: String
            var progress: Progress?
            /// Tints of the thread's recent phases, oldest first.
            var trail: [String]
            var link: String?
            /// Opens Luft's snooze choices for the thread; only while it works.
            var snoozeLink: String?

            enum CodingKeys: String, CodingKey {
                case id, headline, detail, phase, symbol, tint, progress, trail, link
                case snoozeLink = "snooze_link"
            }

            var finished: Bool { ["needs_you", "done", "failed"].contains(phase) }

            init(from decoder: Decoder) throws {
                let values = try decoder.container(keyedBy: CodingKeys.self)
                id = try values.decode(String.self, forKey: .id)
                headline = try values.decodeIfPresent(String.self, forKey: .headline) ?? ""
                detail = try values.decodeIfPresent(String.self, forKey: .detail) ?? ""
                phase = try values.decodeIfPresent(String.self, forKey: .phase) ?? ""
                symbol = try values.decodeIfPresent(String.self, forKey: .symbol) ?? "sparkles"
                tint = try values.decodeIfPresent(String.self, forKey: .tint) ?? "gray"
                progress = try? values.decodeIfPresent(Progress.self, forKey: .progress)
                trail = (try? values.decodeIfPresent([String].self, forKey: .trail)) ?? []
                link = try values.decodeIfPresent(String.self, forKey: .link)
                snoozeLink = try? values.decodeIfPresent(String.self, forKey: .snoozeLink)
            }
        }

        var v: Int
        var summary: Summary
        var threads: [Thread]
        var fallback: String

        var supported: Bool { v <= Self.supportedVersion }

        init(v: Int, summary: Summary, threads: [Thread], fallback: String) {
            self.v = v
            self.summary = summary
            self.threads = threads
            self.fallback = fallback
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            v = try values.decodeIfPresent(Int.self, forKey: .v) ?? Self.supportedVersion
            summary = try values.decode(Summary.self, forKey: .summary)
            threads = try values.decodeIfPresent([Thread].self, forKey: .threads) ?? []
            fallback = try values.decodeIfPresent(String.self, forKey: .fallback) ?? summary.headline
        }

        /// What the app shows from starting the activity until the server's first push.
        static let starting = ContentState(
            v: supportedVersion,
            summary: Summary(headline: "Threads working", phase: "Starting", symbol: "sparkles", tint: "gray"),
            threads: [],
            fallback: "Threads working."
        )
    }

    /// The app's UUID for this activity, which the server registration is keyed by.
    let registrationID: String
    /// The Luft profile that registered it, so a profile switch can end it.
    let profileID: String
    /// The Luft server of that profile.
    let server: String

    /// Where tapping the activity outside a thread leads: the threads list.
    var threadsURL: URL? {
        var url = URLComponents()
        url.scheme = "luft"
        url.host = "app"
        url.path = "/threads"
        url.queryItems = [URLQueryItem(name: "server", value: server)]
        return url.url
    }

    /// A thread's link, accepted only as a Luft navigation link; the app's
    /// router still checks it belongs to a saved profile's server.
    func url(for thread: ContentState.Thread) -> URL? {
        appURL(thread.link)
    }

    /// Where the thread's Snooze leads, checked the same way.
    func snoozeURL(for thread: ContentState.Thread) -> URL? {
        appURL(thread.snoozeLink)
    }

    private func appURL(_ link: String?) -> URL? {
        guard let link, let url = URL(string: link),
              url.scheme == "luft", url.host == "app" else { return nil }
        return url
    }
}

// swiftlint:enable nesting
