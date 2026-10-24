import SwiftUI

/// Bounded, native Markdown presentation. No HTML, remote images, WebView or
/// executable diagrams. Code and unsupported syntax remain selectable text.
struct AtlasMarkdown: View {
    let source: String
    @ScaledMetric(relativeTo: .body) private var tableColumnWidth: CGFloat = 200

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(AtlasMarkdownBlock.parse(source).enumerated()), id: \.offset) { _, block in
                switch block {
                case let .code(language, text):
                    VStack(alignment: .leading, spacing: 6) {
                        if !language.isEmpty { Text(language).font(.caption).foregroundStyle(.secondary) }
                        ScrollView(.horizontal) { Text(text).font(.callout.monospaced()).textSelection(.enabled) }
                    }
                    .padding(12).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                case let .heading(_, text):
                    Text(Self.inline(text)).font(.body.weight(.semibold)).textSelection(.enabled)
                        .accessibilityAddTraits(.isHeader)
                case let .quote(text):
                    HStack(alignment: .top) {
                        RoundedRectangle(cornerRadius: 2).fill(.secondary).frame(width: 3)
                        Text(Self.inline(text)).foregroundStyle(.secondary).textSelection(.enabled)
                    }.fixedSize(horizontal: false, vertical: true)
                case let .list(marker, text):
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(marker).foregroundStyle(.secondary)
                        Text(Self.inline(text)).textSelection(.enabled)
                    }
                case let .table(rows):
                    ScrollView(.horizontal) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                                GridRow {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        Text(Self.inline(cell)).fontWeight(index == 0 ? .semibold : .regular)
                                            .textSelection(.enabled)
                                            .frame(width: tableColumnWidth, alignment: .leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                if index == 0 { Divider().gridCellUnsizedAxes(.horizontal) }
                            }
                        }
                    }
                case .rule: Divider()
                case let .paragraph(text): Text(Self.inline(text)).textSelection(.enabled)
                }
            }
        }
        .font(.body)
        .environment(\.openURL, OpenURLAction { url in
            ["https", "http", "mailto"].contains(url.scheme?.lowercased() ?? "") ? .systemAction : .discarded
        })
    }

    static func inline(_ source: String) -> AttributedString {
        var value = (try? AttributedString(markdown: source, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(source)
        for run in value.runs {
            if let link = run.link, !["https", "http", "mailto"].contains(link.scheme?.lowercased() ?? "") {
                value[run.range].link = nil
            }
        }
        return value
    }
}

enum AtlasMarkdownBlock: Equatable {
    case paragraph(String), heading(Int, String), code(String, String), quote(String), list(String, String), table([[String]]), rule

    static func parse(_ source: String) -> [Self] {
        let lines = String(source.prefix(16_000)).replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [Self] = []
        var paragraph: [String] = []
        var index = 0
        func flush() {
            if !paragraph.isEmpty { blocks.append(.paragraph(paragraph.joined(separator: "\n"))); paragraph = [] }
        }
        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flush()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                index += 1
                while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    code.append(lines[index]); index += 1
                }
                blocks.append(.code(language, code.joined(separator: "\n")))
            } else if trimmed.isEmpty {
                flush()
            } else if index + 1 < lines.count, line.contains("|"), isTableSeparator(lines[index + 1]) {
                flush()
                var rows = [cells(line)]
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(cells(lines[index])); index += 1
                }
                blocks.append(.table(rows)); continue
            } else if let block = lineBlock(trimmed) {
                flush(); blocks.append(block)
            } else { paragraph.append(line) }
            index += 1
        }
        flush()
        return blocks
    }

    private static func lineBlock(_ trimmed: String) -> Self? {
        if ["---", "***", "___"].contains(trimmed) { return .rule }
        if trimmed.hasPrefix("#"), let space = trimmed.firstIndex(of: " "),
           trimmed[..<space].allSatisfy({ $0 == "#" }), trimmed.distance(from: trimmed.startIndex, to: space) <= 6 {
            return .heading(trimmed.distance(from: trimmed.startIndex, to: space), String(trimmed[trimmed.index(after: space)...]))
        }
        if trimmed.hasPrefix("> ") { return .quote(String(trimmed.dropFirst(2))) }
        if ["- ", "* ", "+ "].contains(where: { trimmed.hasPrefix($0) }) { return .list("•", String(trimmed.dropFirst(2))) }
        if let dot = trimmed.firstIndex(of: "."), !trimmed[..<dot].isEmpty,
           trimmed[..<dot].allSatisfy(\.isNumber), trimmed[dot...].hasPrefix(". ") {
            return .list(String(trimmed[...dot]), String(trimmed[trimmed.index(dot, offsetBy: 2)...]))
        }
        return nil
    }

    private static func cells(_ line: String) -> [String] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("|") { text.removeFirst() }
        if text.hasSuffix("|") { text.removeLast() }
        return text.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let values = cells(line)
        return !values.isEmpty && values.allSatisfy {
            let value = $0.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return value.count >= 3 && value.allSatisfy { $0 == "-" }
        }
    }
}
