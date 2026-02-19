public struct APKMetadata: Equatable, Sendable {
    public let packageName: String
    public let versionName: String
    public let versionCode: String
    public let displayName: String

    public init(packageName: String, versionName: String, versionCode: String, displayName: String) {
        self.packageName = packageName
        self.versionName = versionName
        self.versionCode = versionCode
        self.displayName = displayName
    }
}
