import Foundation

public struct BuildData: Encodable, Sendable {
    public let unique_identifier: String
    public let version: Int8
    public let time_started_recording: Double
    public let time_stopped_recording: Double
    public let duration: Int
    public let error_count: Int
    public let status: String
    public let category: String
    public let targets: [Target]
    public let issues: [Issue]
    public let files: [File]
    public let cacheable_tasks: [CacheableTask]
    public let cas_outputs: [CASOutput]
}
