import Foundation

extension URL {
    public static func isValid(_ url: String) -> Bool {
        var valid = false
        /**
         Xcode 15 introduced breaking changes in the URL constructor that we need to account for.
         */
        if #available(macOS 14.0, *) {
            valid = URL(string: url, encodingInvalidCharacters: false) != nil
        } else {
            valid = URL(string: url) != nil
        }
        return valid
    }
}
