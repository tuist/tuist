import ProjectDescription
public extension String {
    /// Returns a canonical bundle Id for the target with the
    /// given name
    /// - parameter target: the name of the target
    /// - returns: the bundle id for the given target
    static func bundleId(for target: String) -> String {
        return "io.tuist.\(target)"
    }
}