import Foundation
import Noora
import TuistNooraExtension
import TuistServer

enum RunnerVolumeOutput {
    static func volumeRow(_ volume: RunnerVolumesPage.volumesPayloadPayload) -> [String] {
        [
            volume.id, volume.key, volume.repository, "Linux · \(volume.architecture)",
            bytes(volume.used_bytes, unmeasured: volume.unmeasured_copies),
            bytes(volume.capacity_bytes, unmeasured: volume.unmeasured_capacity_copies),
            volume.last_used_at.map(Formatters.formatDate) ?? "Never",
        ]
    }

    static func jobRow(_ job: RunnerVolumeJobsPage.jobsPayloadPayload) -> [String] {
        [
            String(job.workflow_job_id), job.job_name ?? "Unknown", job.workflow_name ?? "Unknown",
            job.cache_status.capitalized, job.cache_hit.map { $0 ? "Hit" : "Miss" } ?? "Not reported",
            bytes(job.used_bytes), job.mounted_at.map(Formatters.formatDate) ?? "Not mounted",
        ]
    }

    static func details(_ volume: RunnerVolume) -> String {
        [
            "Volume".bold(),
            "ID: \(volume.id)",
            "Name: \(volume.key)",
            "Repository: \(volume.repository)",
            "Provider: \(volume.provider == "github" ? "GitHub" : volume.provider == "gitlab" ? "GitLab" : "Buildkite")",
            "Platform: Linux · \(volume.architecture)",
            "Used space: \(bytes(volume.used_bytes, unmeasured: volume.unmeasured_copies))",
            "Capacity: \(bytes(volume.capacity_bytes, unmeasured: volume.unmeasured_capacity_copies))",
            "Last used: \(volume.last_used_at.map(Formatters.formatDate) ?? "Never")",
        ].joined(separator: "\n")
    }

    static func analyticsSummary(_ analytics: RunnerVolumeAnalytics) -> String {
        let latest = analytics.storage.last
        return [
            "Volume analytics".bold(),
            "Period: \(Formatters.formatDate(analytics.period.start)) – \(Formatters.formatDate(analytics.period.end))",
            "Volumes: \(latest.map { String($0.volumes) } ?? "Not reported")",
            "Used space: \(bytes(latest?.used_bytes, unmeasured: latest?.unmeasured_copies ?? 0))",
            "Job runs: \(analytics.activity.job_runs)",
            "Cache hit rate: \(percentage(analytics.activity.hit_rate))",
            "Previous period hit rate: \(percentage(analytics.previous_activity.hit_rate))",
            "Hit rate change: \(analytics.trends.hit_rate_percentage_points.map { String(format: "%+.1f percentage points", $0) } ?? "Not available")",
            "Used space change: \(percentage(analytics.trends.used_bytes.percent, signed: true))",
        ].joined(separator: "\n")
    }

    static func bytes(_ value: Int?, unmeasured: Int = 0) -> String {
        guard let value else { return "Not reported" }
        let formatted = Formatters.formatBytes(value)
        return unmeasured > 0 ? "\(formatted) (partial)" : formatted
    }

    static func percentage(_ value: Double?, signed: Bool = false) -> String {
        guard let value else { return "Not available" }
        return String(format: signed ? "%+.1f%%" : "%.1f%%", value)
    }
}
