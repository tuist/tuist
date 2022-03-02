import Foundation

/// Language to use in target action. Can be initialized with String which should be a valid language code or used as pre-defined pseudo language.
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
extension SchemeLanguage {
    public static var doubleLengthPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageDoubleLocalizedStrings")
    }

    public static var rightToLeftPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageRightToLeftLayoutDirection")
    }

    public static var accentedPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageAccentedLatin")
    }

    public static var boundedStringPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageBoundedString")
    }

    public static var rightToLeftWithStringsPseudoLanguage: SchemeLanguage {
        SchemeLanguage(identifier: "IDELaunchSchemeLanguageRLO")
    }
}
