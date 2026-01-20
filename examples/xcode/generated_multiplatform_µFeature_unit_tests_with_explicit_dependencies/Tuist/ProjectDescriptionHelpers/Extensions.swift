import ProjectDescription

extension Destinations {
    public static func destinations(for platforms: Set<Platform>) -> Destinations {
        var set: Destinations = []
        if platforms.contains(.iOS) {
            set.formUnion([.iPhone, .iPad])
        }

        if platforms.contains(.watchOS) {
            set.insert(.appleWatch)
        }

        if platforms.contains(.macOS) {
            set.insert(.mac)
        }

        return set
    }
}

extension DeploymentTargets {
    public static func deploymentTargets(for platforms: Set<Platform>) -> DeploymentTargets {
        var iOS: String? = nil
        var watchOS: String? = nil
        var macOS: String? = nil
        var visionOS: String? = nil

        if platforms.contains(.iOS) {
            iOS = "16.0"
        }

        if platforms.contains(.watchOS) {
            watchOS = "9.0"
        }

        if platforms.contains(.macOS) {
            macOS = "13.0"
        }

        if platforms.contains(.visionOS) {
            visionOS = "1.0"
        }

        return .multiplatform(iOS: iOS, macOS: macOS, watchOS: watchOS, visionOS: visionOS)
    }
}
