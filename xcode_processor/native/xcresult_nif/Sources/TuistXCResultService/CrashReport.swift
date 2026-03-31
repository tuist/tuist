import Foundation
import Path

public struct CrashReport: Encodable, Sendable {
    public let exceptionType: String?
    public let signal: String?
    public let exceptionSubtype: String?
    public let filePath: AbsolutePath
    public let triggeredThreadFrames: String?

    enum CodingKeys: String, CodingKey {
        case exceptionType = "exception_type"
        case signal
        case exceptionSubtype = "exception_subtype"
        case filePath = "file_path"
        case triggeredThreadFrames = "triggered_thread_frames"
    }

    public init(
        exceptionType: String?,
        signal: String?,
        exceptionSubtype: String?,
        filePath: AbsolutePath,
        triggeredThreadFrames: String? = nil
    ) {
        self.exceptionType = exceptionType
        self.signal = signal
        self.exceptionSubtype = exceptionSubtype
        self.filePath = filePath
        self.triggeredThreadFrames = triggeredThreadFrames
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(exceptionType, forKey: .exceptionType)
        try container.encodeIfPresent(signal, forKey: .signal)
        try container.encodeIfPresent(exceptionSubtype, forKey: .exceptionSubtype)
        try container.encode(filePath.pathString, forKey: .filePath)
        try container.encodeIfPresent(triggeredThreadFrames, forKey: .triggeredThreadFrames)
    }
}
