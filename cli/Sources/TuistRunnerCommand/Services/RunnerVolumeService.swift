import ArgumentParser
import Foundation
import Noora
import TuistConfigLoader
import TuistEnvironment
import TuistNooraExtension
import TuistServer

struct RunnerVolumeService {
    typealias VolumeList = Operations.listRunnerVolumes.Output.Ok.Body.jsonPayload
    typealias VolumeJobs = Operations.listRunnerVolumeJobs.Output.Ok.Body.jsonPayload
    typealias VolumeDetails = Operations.getRunnerVolume.Output.Ok.Body.jsonPayload
    typealias VolumeAnalytics = Operations.getRunnerVolumeAnalytics.Output.Ok.Body.jsonPayload

    let client: Client
    let account: String
    let json: Bool

    static func resolve(_ options: RunnerVolumeOptions) async throws -> RunnerVolumeService {
        let directory = try await Environment.current.pathRelativeToWorkingDirectory(options.path)
        let config = try await ConfigLoader().loadConfig(path: directory)
        guard let account = options.account ?? config.fullHandle?.split(separator: "/").first.map(String.init),
              !account.isEmpty
        else { throw ValidationError("Pass --account or configure a project full handle.") }
        let url = try ServerEnvironmentService().url(configServerURL: config.url)
        return RunnerVolumeService(client: .authenticated(serverURL: url), account: account, json: options.json)
    }

    func list(
        name: String?, repository: String?, sort: RunnerVolumeSort?, order: RunnerVolumeSortOrder?,
        pagination: RunnerVolumePagination
    ) async throws {
        let response = try await fetchList(
            name: name,
            repository: repository,
            sort: sort,
            order: order,
            page: pagination.page,
            pageSize: pagination.pageSize
        )
        if json {
            try Noora.current.json(response)
            return
        }
        guard !response.volumes.isEmpty else {
            Noora.current.passthrough("No volumes found on page \(pagination.page).")
            return
        }
        try await Noora.current.paginatedTable(
            headers: ["ID", "Volume", "Repository", "Platform", "Used space", "Capacity", "Last used"],
            pageSize: pagination.pageSize,
            totalPages: response.pagination_metadata.total_pages,
            startPage: pagination.page - 1,
            loadPage: { pageIndex in
                if pageIndex == pagination.page - 1 { return response.volumes.map(Self.volumeRow) }
                let page = try await fetchList(
                    name: name, repository: repository, sort: sort, order: order,
                    page: pageIndex + 1, pageSize: pagination.pageSize
                )
                return page.volumes.map(Self.volumeRow)
            }
        )
    }

    private func fetchList(
        name: String?,
        repository: String?,
        sort: RunnerVolumeSort?,
        order: RunnerVolumeSortOrder?,
        page: Int,
        pageSize: Int
    ) async throws -> VolumeList {
        let response = try await client.listRunnerVolumes(.init(
            path: .init(account_handle: account),
            query: .init(
                name: name,
                page: page,
                page_size: pageSize,
                repository: repository,
                sort_by: sort.flatMap { .init(rawValue: $0.rawValue) },
                sort_order: order.flatMap { .init(rawValue: $0.rawValue) }
            )
        ))
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func show(_ id: String) async throws {
        let response = try await client.getRunnerVolume(.init(path: .init(account_handle: account, volume_id: id)))
        switch response {
        case let .ok(value):
            let volume = try value.body.json
            if json {
                try Noora.current.json(volume)
            } else {
                Noora.current.passthrough("\(Self.details(volume))")
            }
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func jobs(_ id: String, pagination: RunnerVolumePagination) async throws {
        let response = try await fetchJobs(id, page: pagination.page, pageSize: pagination.pageSize)
        if json {
            try Noora.current.json(response)
            return
        }
        guard !response.jobs.isEmpty else {
            Noora.current.passthrough("No jobs found on page \(pagination.page) for this volume.")
            return
        }
        try await Noora.current.paginatedTable(
            headers: ["ID", "Job", "Workflow", "Cache status", "Cache", "Used space", "Mounted at"],
            pageSize: pagination.pageSize,
            totalPages: response.pagination_metadata.total_pages,
            startPage: pagination.page - 1,
            loadPage: { pageIndex in
                if pageIndex == pagination.page - 1 { return response.jobs.map(Self.jobRow) }
                let page = try await fetchJobs(id, page: pageIndex + 1, pageSize: pagination.pageSize)
                return page.jobs.map(Self.jobRow)
            }
        )
    }

    private func fetchJobs(_ id: String, page: Int, pageSize: Int) async throws -> VolumeJobs {
        let response = try await client.listRunnerVolumeJobs(.init(
            path: .init(account_handle: account, volume_id: id),
            query: .init(page: page, page_size: pageSize)
        ))
        switch response {
        case let .ok(value): return try value.body.json
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func analytics(_ id: String?, start: Date?, end: Date?) async throws {
        let response = try await client.getRunnerVolumeAnalytics(.init(
            path: .init(account_handle: account), query: .init(end: end, start: start, volume_id: id)
        ))
        switch response {
        case let .ok(value):
            let analytics = try value.body.json
            if json {
                try Noora.current.json(analytics)
            } else {
                Noora.current.passthrough("\(Self.analyticsSummary(analytics))")
            }
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    func clear(_ id: String) async throws {
        let response = try await client.clearRunnerVolume(.init(path: .init(account_handle: account, volume_id: id)))
        switch response {
        case let .ok(value):
            let result = try value.body.json
            if json {
                try Noora.current.json(result)
            } else {
                Noora.current.success("Saved contents cleared for volume \(id).")
            }
        case let .badRequest(value): throw ValidationError(try value.body.json.message)
        case let .forbidden(value): throw ValidationError(try value.body.json.message)
        case let .notFound(value): throw ValidationError(try value.body.json.message)
        case .tooManyRequests: throw ValidationError("Too many requests. Wait before retrying.")
        case let .undocumented(statusCode, _):
            throw ValidationError(
                "The server could not complete the volume request (HTTP \(statusCode)). Check your authentication and server version."
            )
        }
    }

    static func volumeRow(_ volume: VolumeList.volumesPayloadPayload) -> [String] {
        [
            volume.id, volume.key, volume.repository, "Linux · \(volume.architecture)",
            bytes(volume.used_bytes, unmeasured: volume.unmeasured_copies),
            bytes(volume.capacity_bytes, unmeasured: volume.unmeasured_capacity_copies),
            volume.last_used_at.map(Formatters.formatDate) ?? "Never",
        ]
    }

    static func jobRow(_ job: VolumeJobs.jobsPayloadPayload) -> [String] {
        [
            String(job.workflow_job_id), job.job_name ?? "Unknown", job.workflow_name ?? "Unknown",
            job.cache_status.capitalized, job.cache_hit.map { $0 ? "Hit" : "Miss" } ?? "Not reported",
            bytes(job.used_bytes), job.mounted_at.map(Formatters.formatDate) ?? "Not mounted",
        ]
    }

    static func details(_ volume: VolumeDetails) -> String {
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

    static func analyticsSummary(_ analytics: VolumeAnalytics) -> String {
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
