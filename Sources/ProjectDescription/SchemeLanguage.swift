import Foundation

public struct SchemeLanguage: Codable, Equatable, ExpressibleByStringLiteral {
    public let identifier: String

    public init(identifier: String) {
        self.identifier = identifier
    }

    public init(stringLiteral value: String) {
        identifier = value
    }
}

// Pre-defined languages
public extension SchemeLanguage {
    static var doubleLengthPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageDoubleLocalizedStrings")
    }

    static var rightToLeftPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageRightToLeftLayoutDirection")
    }

    static var accentedPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageAccentedLatin")
    }

    static var boundedStringPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageBoundedString")
    }

    static var rightToLeftWithStringsPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageRLO")
    }
}
