import Foundation
import Noora
import TuistNooraExtension
import TuistServer

enum SandboxOutput {
    static func row(_ sandbox: SandboxesPage.sandboxesPayloadPayload) -> [String] {
        [
            sandbox.id, status(sandbox.status, state: sandbox.state.rawValue), String(sandbox.vcpus),
            megabytes(sandbox.memory_mb),
            sandbox.last_active_at.map(Formatters.formatDate) ?? "Never",
        ]
    }

    static func details(_ sandbox: ServerSandbox) -> String {
        var lines = [
            "Sandbox".bold(),
            "ID: \(sandbox.id)",
            "Status: \(status(sandbox.status, state: sandbox.state.rawValue))",
            "vCPUs: \(sandbox.vcpus)",
            "Memory: \(megabytes(sandbox.memory_mb))",
            "Disk: \(sandbox.workspace_gb) GB",
            "Created: \(Formatters.formatDate(sandbox.inserted_at))",
            "Last active: \(sandbox.last_active_at.map(Formatters.formatDate) ?? "Never")",
        ]
        if let pausedAt = sandbox.paused_at { lines.append("Paused: \(Formatters.formatDate(pausedAt))") }
        if let archivedAt = sandbox.archived_at {
            let size = sandbox.archive_bytes.map { " (\(Formatters.formatBytes($0)))" } ?? ""
            lines.append("Archived: \(Formatters.formatDate(archivedAt))\(size)")
        }
        if let error = sandbox.error_message { lines.append("Error: \(error)") }
        return lines.joined(separator: "\n")
    }

    static func analytics(_ analytics: SandboxAnalytics) -> String {
        let concurrency = analytics.concurrency
        let peak = (
            vcpus: concurrency.points.map(\.vcpus).max() ?? 0,
            memory: concurrency.points.map(\.memory_gb).max() ?? 0,
            disk: concurrency.points.map(\.disk_gb).max() ?? 0
        )
        return [
            "Sandbox analytics".bold(),
            "Period: \(Formatters.formatDate(analytics.period.start)) – \(Formatters.formatDate(analytics.period.end))",
            "vCPU-hours: \(String(format: "%.1f", analytics.vcpu_hours))",
            "Sandboxes created: \(analytics.created.count) (\(trend(analytics.created.trend)))",
            "Session duration: \(duration(analytics.session_duration.count, analytics.session_duration.p50_ms, analytics.session_duration.p90_ms))",
            "Setup: \(duration(analytics.setup.count, analytics.setup.p50_ms, analytics.setup.p90_ms))",
            "Time to start: \(duration(analytics.time_to_start.count, analytics.time_to_start.p50_ms, analytics.time_to_start.p90_ms))",
            "Peak vCPUs: \(peak.vcpus) of \(concurrency.limits.vcpus) (\(concurrency.in_use.vcpus) in use now)",
            "Peak memory: \(gigabytes(peak.memory)) of \(gigabytes(concurrency.limits.memory_gb)) (\(gigabytes(concurrency.in_use.memory_gb)) in use now)",
            "Peak disk: \(gigabytes(peak.disk)) of \(gigabytes(concurrency.limits.disk_gb)) (\(gigabytes(concurrency.in_use.disk_gb)) on nodes now)",
        ].joined(separator: "\n")
    }

    /// The status the dashboard shows, which servers before it was added do not send.
    static func status(_ status: String?, state: String) -> String {
        (status ?? state).capitalized
    }

    private static func megabytes(_ value: Int) -> String {
        value % 1024 == 0 ? "\(value / 1024) GB" : "\(value) MB"
    }

    private static func gigabytes(_ value: Double) -> String {
        String(format: value.rounded() == value ? "%.0f GB" : "%.1f GB", value)
    }

    private static func duration(_ count: Int, _ p50: Int, _ p90: Int) -> String {
        guard count > 0 else { return "None in this period" }
        return "p50 \(milliseconds(p50)), p90 \(milliseconds(p90)) across \(count)"
    }

    /// Sessions run for hours, so durations past a minute read as "1h 1m" or "3m 40s" rather than raw seconds.
    private static func milliseconds(_ value: Int) -> String {
        let seconds = value / 1000
        guard seconds >= 60 else { return Formatters.formatDuration(value) }
        let (hours, minutes) = (seconds / 3600, seconds % 3600 / 60)
        return hours > 0 ? "\(hours)h \(minutes)m" : "\(minutes)m \(seconds % 60)s"
    }

    private static func trend(_ value: Double) -> String {
        String(format: "%+.1f%% against the previous period", value)
    }
}
