import Foundation

/// Fictional, offline data for screenshots of the production native views.
enum AtlasSocialPreviewData {
    static var enabled: Bool { ProcessInfo.processInfo.arguments.contains("--social-screenshots") }

    static var threads: [[String: Any]] {
        let conversations: [(String, String, String, String, Int)] = [
            ("001", "Next week’s customer calls", "Three accounts and clear next steps.", "private", 0),
            ("002", "Northstar renewal", "Final terms ready for Tuesday’s review.", "shared", 0),
            ("004", "October cash flow", "€120k in cash. Eight months of runway.", "private", 0),
            ("003", "Fern Studio onboarding", "A short checklist for the pilot, owners, and success criteria.", "shared", -1),
            ("005", "Berlin team week", "Workshop ideas, travel plans, and a little room to explore.", "shared", -1),
            ("006", "A calmer Monday morning", "A weekly brief covering customers, cash, and the team.", "private", -3),
            ("007", "Hiring our next teammate", "Interview questions and a practical first-week plan.", "private", -4)
        ]
        return conversations.enumerated().map { index, conversation in
            let (suffix, title, summary, kind, days) = conversation
            let day = Calendar.current.date(byAdding: .day, value: days, to: Calendar.current.startOfDay(for: Date()))!
            let date = day.addingTimeInterval(Double(9 * 3600 + 32 * 60 - index * 20 * 60))
            return [
                "id": "01922cc0-0000-7000-8000-000000000\(suffix)", "title": title, "summary": summary,
                "kind": kind, "status": "active", "origin": "manual", "owner_id": "preview-self",
                "participants": [["id": "preview-self", "name": "Taylor"]] + (kind == "shared" ? [["id": "online", "name": "Jordan"]] : []),
                "updated_at": ISO8601DateFormatter().string(from: date)
            ]
        }
    }

    static func messages(threadID: String) -> [[String: Any]] {
        let question: String
        let answer: String
        if threadID.hasSuffix("004") {
            question = "How is our runway looking this month?"
            answer = """
                ## Eight months of runway

                You have **€120,000** across three accounts. Average monthly net burn is **€15,000**.

                - **September:** €30,000 in, €42,000 out.
                - **October so far:** €18,001 in, €27,001 out.

                October is still in progress, so I’d compare complete months before changing the forecast.
                """
        } else {
            question = "Give me a quick brief for next week’s customer calls."
            answer = """
                ## Three accounts to prioritise

                **Northstar · Renewal**
                The €24,500 agreement renews next month. Confirm terms with Jordan on Tuesday.

                **Fern Studio · Pilot**
                Set a two-week pilot goal and name an owner before kickoff.

                **Harbor Labs · Expansion**
                A second team is joining. Confirm seats and timing before quoting.

                Start with Northstar: it has the nearest deadline.
                """
        }
        let date = ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: Date()).addingTimeInterval(9 * 3600 + 30 * 60))
        return [
            ["id": "social-question", "kind": "human", "body": question, "author_id": "preview-self",
             "author_name": "Taylor", "inserted_at": date, "tool_input": "", "tool_output": ""],
            ["id": "social-reply", "kind": "agent", "body": answer, "author_name": "Pip", "inserted_at": date,
             "tool_input": "", "tool_output": ""]
        ]
    }

    static var accounts: [[String: Any]] {
        let companies: [(String, String, String, String)] = [
            ("Northstar", "customer", "active", "24500"),
            ("Fern Studio", "prospect", "trial", "6000"),
            ("Harbor Labs", "customer", "active", "18000"),
            ("Juniper Works", "customer", "active", "12000"),
            ("Fieldnote", "prospect", "trial", "8400"),
            ("Kite & Compass", "customer", "active", "9600"),
            ("Morrow Systems", "prospect", "trial", "15000")
        ]
        return companies.enumerated().map { index, company in
            let (name, segment, status, value) = company
            return ["id": "account-\(index + 1)", "can_edit": true, "can_delete": true,
                    "fields": ["name": name, "segment": segment, "status": status, "currency": "EUR",
                               "current_value": value, "contract_value": value, "contract_currency": "EUR", "hosting": "cloud"]]
        }
    }
}
