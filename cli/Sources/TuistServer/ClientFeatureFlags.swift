import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import TuistEnvironment

public enum ClientFeatureFlags {
    public static let headerName = "x-tuist-feature-flags"
    private static let environmentPrefix = "TUIST_FEATURE_FLAG_"

    public static func headerValue(environment: Environmenting = Environment.current) -> String? {
        let featureFlags = featureFlags(environment: environment)
        return featureFlags.isEmpty ? nil : featureFlags.joined(separator: ",")
    }

    public static func addHeader(to request: inout URLRequest, environment: Environmenting = Environment.current) {
        guard let headerValue = headerValue(environment: environment) else { return }
        request.setValue(headerValue, forHTTPHeaderField: headerName)
    }

    static func featureFlags(environment: Environmenting = Environment.current) -> [String] {
        Array(
            Set(
                environment.variables.compactMap { variable in
                    featureName(from: variable.key)
                }
            )
        )
        .sorted()
    }

    static func featureName(from variableName: String) -> String? {
        guard variableName.hasPrefix(environmentPrefix) else { return nil }

        let featureName = String(variableName.dropFirst(environmentPrefix.count))
        return featureName.isEmpty ? nil : featureName
    }
}
