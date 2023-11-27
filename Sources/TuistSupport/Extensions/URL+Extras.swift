import Foundation

extension URL {
    public static func isValid(_ url: String) -> Bool {
        /**
         Xcode 15 introduced breaking changes in the URL constructor that we need to account for.
         */
        #if swift(>=5.9)
            return URL(string: url, encodingInvalidCharacters: false) != nil
        #else
            return URL(string: url) != nil
        #endif
    }
}
