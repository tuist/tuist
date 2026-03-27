import Foundation

public struct CrashReport: Encodable, Sendable {
    public let exceptionType: String?
    public let signal: String?
    public let exceptionSubtype: String?
    public let filePath: String
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
        filePath: String,
        triggeredThreadFrames: String? = nil
    ) {
        self.exceptionType = exceptionType
        self.signal = signal
        self.exceptionSubtype = exceptionSubtype
        self.filePath = filePath
        self.triggeredThreadFrames = triggeredThreadFrames
    }
}
