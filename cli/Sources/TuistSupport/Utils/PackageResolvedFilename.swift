import Foundation

public func packageResolvedFilename(
    environment: Environmenting = Environment.current
) -> String {
    guard
        let value = environment.variables["TUIST_PACKAGE_RESOLVED_NAME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
        !value.isEmpty
    else {
        return ".package.resolved"
    }
    return value
}
