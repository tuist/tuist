import Foundation

/// A language to use for run and test actions.
public struct SchemeLanguage: Codable, Equatable, ExpressibleByStringLiteral {
    public let identifier: String

    /// Creates a new scheme language.
    /// - Parameter identifier: A valid language code or a pre-defined pseudo language.
    public init(identifier: String) {
        self.identifier = identifier
    }

    /// Creates a new scheme language.
    /// - Parameter stringLiteral: A valid language code or a pre-defined pseudo language.
    public init(stringLiteral: String) {
        identifier = stringLiteral
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
