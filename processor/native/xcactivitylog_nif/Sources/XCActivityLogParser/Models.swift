import Foundation

public struct ParsedBuildData: Encodable, Sendable {
    public let unique_identifier: String
    public let version: Int8
    public let time_started_recording: Double
    public let time_stopped_recording: Double
    public let duration: Int
    public let error_count: Int
    public let status: String
    public let category: String
    public let targets: [ParsedTarget]
    public let issues: [ParsedIssue]
    public let files: [ParsedFile]
    public let cacheable_tasks: [ParsedCacheableTask]
    public let cas_outputs: [ParsedCASOutput]
}

public struct ParsedTarget: Encodable, Sendable {
    public let name: String
    public let project: String
    public let build_duration: Int
    public let compilation_duration: Int
    public let status: String
}

public struct ParsedIssue: Encodable, Sendable {
    public let type: String
    public let target: String
    public let project: String
    public let title: String
    public let signature: String
    public let step_type: String
    public let path: String?
    public let message: String?
    public let starting_line: Int
    public let ending_line: Int
    public let starting_column: Int
    public let ending_column: Int
}

public struct ParsedFile: Encodable, Sendable {
    public let type: String
    public let target: String
    public let project: String
    public let path: String
    public let compilation_duration: Int
}

public struct ParsedCacheableTask: Encodable, Sendable {
    public let type: String
    public let status: String
    public let key: String
    public let read_duration: Double?
    public let write_duration: Double?
    public let description: String?
    public let cas_output_node_ids: [String]
}

public struct ParsedCASOutput: Encodable, Sendable {
    public let node_id: String
    public let checksum: String
    public let size: Int
    public let duration: Double
    public let compressed_size: Int
    public let operation: String
    public let type: String?
}
