import Foundation
import Path
import XcodeGraph

/// Rewrites only module declarations and header path tokens, leaving comments, requirements,
/// exports, links, textual/private declarations and submodules intact. Unsupported external
/// module-map references are rejected instead of publishing an artifact tied to its checkout.
enum SwiftPackageModuleMapRelocator {
    struct Result {
        let contents: String
        let references: [AbsolutePath]
    }

    private struct Token {
        let text: String
        let range: NSRange
        let isString: Bool
    }

    static func relocate(_ contents: String, layout: Headers.SourceLayout, framework: Bool) throws -> Result {
        let tokens = try tokenize(contents)
        var replacements: [(NSRange, String)] = []
        var references: [AbsolutePath] = []
        var depth = 0
        var foundModule = false
        for (index, token) in tokens.enumerated() {
            if token.text == "{" { depth += 1 }
            if token.text == "}" { depth -= 1 }
            guard !token.isString else { continue }
            if token.text == "extern" {
                throw SwiftPackageHeadersExportError.unsupported("external module map in \(layout.moduleMap)")
            }
            if token.text == "module", depth == 0 {
                guard index + 1 < tokens.count, tokens[index + 1].text == layout.moduleName else {
                    throw SwiftPackageHeadersExportError.unsupported("multiple or unexpected top-level modules")
                }
                foundModule = true
                let isFramework = index > 0 && tokens[index - 1].text == "framework"
                if framework, !isFramework {
                    replacements.append((NSRange(location: token.range.location, length: 0), "framework "))
                } else if !framework, isFramework {
                    replacements.append((tokens[index - 1].range, ""))
                }
            }
            guard ["header", "umbrella"].contains(token.text), index + 1 < tokens.count,
                  tokens[index + 1].isString
            else { continue }
            let pathToken = tokens[index + 1]
            let pathText = pathToken.text
            guard !pathText.contains("\\") else {
                throw SwiftPackageHeadersExportError.unsupported("escaped header path")
            }
            let path: AbsolutePath
            if pathText.hasPrefix("/") {
                path = try AbsolutePath(validating: pathText)
            } else {
                path = layout.moduleMap.parentDirectory.appending(try RelativePath(validating: pathText))
            }
            guard path.isDescendantOfOrEqual(to: layout.root) else {
                throw SwiftPackageHeadersExportError.unsupported("module map references \(path)")
            }
            let relative: String
            if framework {
                // Clang resolves framework header declarations against Headers/, but umbrella
                // directory declarations against the framework root.
                if layout.usesDirectoryModuleMap {
                    let prefix = token.text == "umbrella" ? "Headers/" : ""
                    relative = prefix + path.relative(to: layout.publicHeaders).pathString
                } else {
                    let prefix = token.text == "umbrella" ? "TuistHeaders/" : "../TuistHeaders/"
                    relative = prefix + path.relative(to: layout.root).pathString
                }
            } else {
                relative = "TuistHeaders/" + path.relative(to: layout.root).pathString
            }
            replacements.append((pathToken.range, "\"\(relative)\""))
            if token.text == "header" { references.append(path) }
        }
        guard foundModule else {
            throw SwiftPackageHeadersExportError.unsupported("missing module \(layout.moduleName)")
        }
        let output = NSMutableString(string: contents)
        for (range, replacement) in replacements.sorted(by: { $0.0.location > $1.0.location }) {
            output.replaceCharacters(in: range, with: replacement)
        }
        return Result(contents: output as String, references: references)
    }

    private static func tokenize(_ contents: String) throws -> [Token] {
        let expression = try NSRegularExpression(
            pattern: #"(?s)/\*.*?\*/|//[^\n]*|"(?:\\.|[^"\\])*"|[A-Za-z_][A-Za-z_0-9.]*|[^\s]"#
        )
        let source = contents as NSString
        return expression.matches(in: contents, range: NSRange(location: 0, length: source.length)).compactMap { match in
            let text = source.substring(with: match.range)
            if text.hasPrefix("//") || text.hasPrefix("/*") { return nil }
            let isString = text.hasPrefix("\"")
            return Token(text: isString ? String(text.dropFirst().dropLast()) : text, range: match.range, isString: isString)
        }
    }
}
