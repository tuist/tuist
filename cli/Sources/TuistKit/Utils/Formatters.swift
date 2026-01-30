import Foundation

enum Formatters {
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

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter
    }()

    static func formatBytes(_ bytes: Int) -> String {
        byteCountFormatter.string(fromByteCount: Int64(bytes))
    }

    static func formatDate(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    static func formatDuration(_ milliseconds: Int) -> String {
        let seconds = TimeInterval(milliseconds) / 1000.0
        if milliseconds < 1000 {
            return "\(milliseconds)ms"
        }
        return durationFormatter.string(from: seconds) ?? "\(Int(seconds))s"
    }

    static func formatTimestamp(_ timestamp: Int) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return formatDate(date)
    }
}
