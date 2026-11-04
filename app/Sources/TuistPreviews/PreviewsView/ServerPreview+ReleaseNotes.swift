import Foundation
import NaturalLanguage
import SwiftUI
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

    /// The direction of the release notes' own language. Paragraphs follow their language, not the interface direction.
    var releaseNotesLayoutDirection: LayoutDirection? {
        guard let releaseNotes, let language = NLLanguageRecognizer.dominantLanguage(for: releaseNotes) else { return nil }
        return Locale.Language(identifier: language.rawValue).characterDirection == .rightToLeft ? .rightToLeft : .leftToRight
    }
}
