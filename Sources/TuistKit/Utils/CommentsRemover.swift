import Foundation

enum CommentsRemover {
    static func removeComments(from code: String) throws -> String {
        let regexPattern = #"//.*?$|/\*[\s\S]*?\*/"#
        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: [.anchorsMatchLines])
            let range = NSRange(location: 0, length: code.utf16.count)
            var cleanCode = regex.stringByReplacingMatches(in: code, options: [], range: range, withTemplate: "")

            cleanCode = cleanCode.replacingOccurrences(of: #"(?m)^\s*\n"#, with: "", options: .regularExpression)

            return cleanCode
        }
    }
}
