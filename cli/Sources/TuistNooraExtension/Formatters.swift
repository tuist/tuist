import Foundation

public enum Formatters {
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    public static func formatBytes(_ bytes: Int) -> String {
        byteCountFormatter.string(fromByteCount: Int64(bytes))
    }

    public static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    public static func formatDuration(_ milliseconds: Int) -> String {
        if milliseconds < 1000 {
            return "\(milliseconds)ms"
        }
        let seconds = Double(milliseconds) / 1000.0
        return String(format: "%.2fs", seconds)
    }

    public static func formatTimestamp(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return formatDate(date)
    }
}
