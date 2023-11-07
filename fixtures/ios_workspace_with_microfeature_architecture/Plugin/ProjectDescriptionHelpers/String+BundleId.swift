import ProjectDescription
extension String {
    /// Returns a canonical bundle Id for the target with the
    /// given name
    /// - parameter target: the name of the target
    /// - returns: the bundle id for the given target
    public static func bundleId(for target: String) -> String {
        "io.tuist.\(target)"
    }
}
