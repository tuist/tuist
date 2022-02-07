import Foundation

struct DotEnvParser {
    /// Parse .env file at the given path
    /// - Parameters:
    ///   - path: path to .env file
    func parse(path: String) -> [String: String] {
        var results: [String: String] = [:]
        if let contents = try? NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) {
            // DotEnv Parsing Logic pulled from https://github.com/SwiftOnTheServer/SwiftDotEnv/blob/master/Sources/DotEnv/DotEnv.swift.
            let lines = String(describing: contents).split { $0 == "\n" || $0 == "\r\n" }.map(String.init)

            for line in lines {
                // ignore comments
                if line[line.startIndex] == "#" {
                    continue
                }

                // ignore lines that appear empty
                if line.trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines).isEmpty {
                    continue
                }

                // extract key and value which are separated by an equals sign
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)

                let key = parts[0].trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)
                var value = parts[1].trimmingCharacters(in: NSCharacterSet.whitespacesAndNewlines)

                // remove surrounding quotes from value & convert remove escape character before any embedded quotes
                if value[value.startIndex] == "\"", value[value.index(before: value.endIndex)] == "\"" {
                    value.remove(at: value.startIndex)
                    value.remove(at: value.index(before: value.endIndex))
                    value = value.replacingOccurrences(of: "\\\"", with: "\"")
                }
                results[key] = value
            }
        }

        return results
    }
}
