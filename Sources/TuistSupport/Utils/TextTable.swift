import Foundation

/// `TextTable` formats data into a textual representation of a table.
///
/// The usage:
///
///     private struct Template {
///         let name: String
///         let description: String
///     }
///
///     private let textTable = TextTable<Template> { [
///         TextTable.Column(title: "Name", value: $0.name),
///         TextTable.Column(title: "Description", value: $0.description),
///     ] }
///
///     let renderedTable = textTable.render(templates)
///     print(renderedTable)
///
/// The output:
///
///     Name     Description
///     ───────  ────────────────
///     default  Default template
///     swiftui  SwiftUI template
///
public struct TextTable<T> {
    private let mapper: (T) -> [Column]

    /// Creates an instance of `TextTable` which is used to table rendering.
    ///
    /// - Parameters:
    ///   - mapper: A function for mapping an instance `T` to an array of columns.
    public init(_ mapper: @escaping (T) -> [Column]) {
        self.mapper = mapper
    }

    /// Returns a string representing the data redered as a table.
    ///
    /// - Parameters:
    ///   - data: A collection of elements to render.
    ///
    /// - Returns: A string representing the data redered as a table.
    public func render<C: Collection>(_ data: C) -> String where C.Iterator.Element == T {
        guard let headerRow = data.first else { return "" }

        var table = ""
        let widths = calculateWidths(for: data)

        // Header
        let headers = mapper(headerRow)
        render(headers: headers, in: &table, widths: widths)

        // Separator
        let separator = Character("─")
        render(separator: separator, in: &table, widths: widths)

        // Data Rows
        data.forEach {
            let row = mapper($0)
            render(row: row, in: &table, widths: widths)
        }

        return table
    }

    private func render(headers: [Column], in table: inout String, widths: [Int]) {
        precondition(headers.count == widths.count)

        let cells = headers.enumerated().map {
            Cell(value: $0.element.title, width: widths[$0.offset])
        }
        render(cells: cells, in: &table)
        table += "\n"
    }

    private func render(separator: Character, in table: inout String, widths: [Int]) {
        let cells = widths.map {
            Cell(value: String(repeating: separator, count: $0), width: $0)
        }
        render(cells: cells, in: &table)
        table += "\n"
    }

    private func render(row: [Column], in table: inout String, widths: [Int]) {
        precondition(row.count == widths.count)

        let cells = row.enumerated().map {
            Cell(value: $0.element.value, width: widths[$0.offset])
        }
        render(cells: cells, in: &table)
        table += "\n"
    }

    private func render(cells: [Cell], in table: inout String) {
        table += cells.map(\.value).joined(separator: "  ")
    }

    private func calculateWidths<C: Collection>(for data: C) -> [Int] where C.Iterator.Element == T {
        guard let first = data.first else { return [] }

        // Headers
        let headers = mapper(first)
        var widths = headers.map(\.title.count)

        // Data Rows
        for element in data {
            let columns = mapper(element)
            for (index, column) in columns.enumerated() {
                widths[index] = max(
                    column.value.description.count,
                    widths[index]
                )
            }
        }

        return widths
    }
}

extension TextTable {
    public struct Column {
        let title: String
        let value: CustomStringConvertible

        public init(title: String, value: CustomStringConvertible) {
            self.title = title
            self.value = value
        }
    }
}

extension TextTable {
    private struct Cell {
        let value: String

        init(value: CustomStringConvertible, width: Int) {
            precondition(
                width >= value.description.count,
                "The width \(width) cannot be smaller than a value description count \(value.description.count)."
            )

            self.value = value.description.padding(toLength: width, withPad: " ", startingAt: 0)
        }
    }
}
