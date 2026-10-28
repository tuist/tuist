import Foundation
import TuistServer

extension ServerPreview {
    var releaseNotesSummary: String? {
        guard let firstLine = releaseNotes?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
            .first
        else { return nil }
        return String(firstLine).trimmingCharacters(in: .whitespaces)
    }
}
