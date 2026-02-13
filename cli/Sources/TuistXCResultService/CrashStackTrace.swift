import Foundation

public struct CrashStackTrace {
    public let id: String
    public let fileName: String
    public let appName: String?
    public let osVersion: String?
    public let exceptionType: String?
    public let signal: String?
    public let exceptionSubtype: String?
    public let rawContent: String

    public init(
        id: String,
        fileName: String,
        appName: String?,
        osVersion: String?,
        exceptionType: String?,
        signal: String?,
        exceptionSubtype: String?,
        rawContent: String
    ) {
        self.id = id
        self.fileName = fileName
        self.appName = appName
        self.osVersion = osVersion
        self.exceptionType = exceptionType
        self.signal = signal
        self.exceptionSubtype = exceptionSubtype
        self.rawContent = rawContent
    }
}
