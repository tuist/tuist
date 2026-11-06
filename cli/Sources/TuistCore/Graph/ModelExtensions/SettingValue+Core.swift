import XcodeGraph

extension SettingValue {
    /// `value` as one item of a build-setting list. Xcode splits a list setting on whitespace and
    /// keeps a double-quoted item whole, so a path with a space stays one argument; backslashes and
    /// quotes inside the value are escaped.
    public static func quoted(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
