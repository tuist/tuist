import SwiftUI
import LuftCore

/// What the composer's text means for looping people in, decided by the Rust
/// core's `compose`: the `@` query being typed and its suggestions, and who a
/// thread would loop in or a hall would suggest inviting.
struct ComposeState: Decodable {
    var content = ""
    var suggestions: [HallPerson] = []
    var mentioned: [HallPerson] = []
    var loop_in: [HallPerson] = []
    var invite: [HallPerson] = []
}

/// The composer's mention state for one conversation. The people come from the
/// organization (`hall_people`); a personal account has none, so it suggests nobody.
@MainActor @Observable
final class Mentions {
    /// `new_thread`, `thread`, `new_hall`, `hall` or `direct`.
    let context: String
    /// Who is already in the conversation, so mentioning them changes nothing.
    var members: [Int] = []
    private(set) var people: [HallPerson] = []
    private(set) var state = ComposeState()

    init(context: String) { self.context = context }

    func load(_ client: AppClient) async {
        guard let data = try? await client.call("hall_people"), let list = data["people"],
              let decoded = try? JSONDecoder().decode([HallPerson].self, from: JSONSerialization.data(withJSONObject: list))
        else { return }
        people = decoded
    }

    /// Recomputes the state for `text`; returns the text to show, which differs after a pick.
    @discardableResult
    func update(_ text: String, pick: Int? = nil) -> String {
        var input: [String: Any] = [
            "context": context, "content": text, "members": members,
            "people": people.map { ["id": $0.id, "handle": $0.handle ?? "", "online": $0.online ?? false] },
        ]
        if let pick { input["pick"] = pick }
        guard let request = try? JSONSerialization.data(withJSONObject: input) else { return text }
        // Pure and fast: called on every edit without the client's serialized queue.
        let output = String(decoding: request, as: UTF8.self).withCString { tuist_app_compose($0) }
        guard let output else { return text }
        let data = Data(String(cString: output).utf8)
        tuist_app_free(output)
        if let next = try? JSONDecoder().decode(ComposeState.self, from: data) { state = next }
        return state.content
    }
}

/// Above the composer: people matching the `@` being typed, then what sending
/// does for the people the message mentions.
struct MentionBar: View {
    let mentions: Mentions
    @Binding var text: String
    /// A hall's name, for the invite note.
    var place: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !mentions.state.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(mentions.state.suggestions) { person in
                            Button { text = mentions.update(text, pick: person.id) } label: {
                                HStack(spacing: 4) {
                                    Text(verbatim: "@\(person.handle ?? "")")
                                    if person.online == true {
                                        Circle().fill(Color.green).frame(width: 6, height: 6).accessibilityHidden(true)
                                    }
                                }
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 12).frame(minHeight: 36)
                                .foregroundStyle(Noora.labelPrimary)
                                .interactiveGlass(in: Capsule())
                                .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("Mention \(person.handle ?? "")"))
                            .accessibilityValue(person.online == true ? Text("Online") : Text(verbatim: ""))
                        }
                    }
                    .padding(.horizontal, 4)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("People to mention"))
            }
            if let note {
                Label { Text(verbatim: note) } icon: {
                    Image(systemName: mentions.context.hasSuffix("thread") ? "person.2.badge.plus" : "person.badge.plus")
                }
                .font(.caption).foregroundStyle(Noora.labelSecondary)
                .padding(.horizontal, 12)
            }
        }
    }

    private var note: String? {
        let names = { (people: [HallPerson]) in people.compactMap { $0.handle.map { "@\($0)" } }.formatted(.list(type: .and)) }
        switch mentions.context {
        case "new_thread", "thread":
            guard !mentions.state.loop_in.isEmpty else { return nil }
            return String(localized: "Sending loops in \(names(mentions.state.loop_in)): they can read and prompt this thread.")
        case "new_hall":
            guard !mentions.state.loop_in.isEmpty else { return nil }
            return String(localized: "Creating the hall invites \(names(mentions.state.loop_in)).")
        case "hall":
            guard !mentions.state.invite.isEmpty else { return nil }
            return String(localized: "\(names(mentions.state.invite)) isn’t in \(place ?? "this hall") yet. You can invite them after sending.")
        default:
            return nil
        }
    }
}
