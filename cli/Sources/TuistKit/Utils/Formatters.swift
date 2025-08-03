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

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
