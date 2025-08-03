import Foundation

enum Formatters {
enum Formatters {
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    static func formatBytes(_ bytes: Int) -> String {
        return byteFormatter.string(fromByteCount: Int64(bytes))
    }
}

    // Cache a single DateFormatter instance to avoid the cost of creating one on each call.
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func formatDate(_ date: Date) -> String {
        return dateFormatter.string(from: date)
    }
}
