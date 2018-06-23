import Basic
import Foundation

/// A file aggregator aggregates the content of multiple files.
protocol FileAggregating: AnyObject {
    /// Aggreates the files at the given paths.
    ///
    /// - Parameters:
    ///   - paths: paths whose content will be aggregated.
    ///   - into: path of the file where the contents will be aggregated into.
    /// - Throws: an error if the aggregation fails.
    func aggregate(_ paths: [AbsolutePath], into: AbsolutePath) throws
}

/// Default file aggreagtor.
final class FileAggregator: FileAggregating {
    /// Aggreates the files at the given paths.
    ///
    /// - Parameters:
    ///   - paths: paths whose content will be aggregated.
    ///   - into: path of the file where the contents will be aggregated into.
    /// - Throws: an error if the aggregation fails.
    func aggregate(_ paths: [AbsolutePath], into: AbsolutePath) throws {
        var paths = paths
        if paths.count == 0 { return }
        let outputStream = OutputStream(toFileAtPath: into.asString, append: true)!
        outputStream.open()
        let first = paths.removeFirst()
        try Data(contentsOf: URL(fileURLWithPath: first.asString)).write(into: outputStream)
        try paths.forEach { path in
            "\n".data(using: .utf8)!.write(into: outputStream)
            try Data(contentsOf: URL(fileURLWithPath: path.asString)).write(into: outputStream)
        }
        outputStream.close()
    }
}

fileprivate extension Data {
    func write(into: OutputStream) {
        _ = withUnsafeBytes {
            into.write($0, maxLength: self.count)
        }
    }
}
