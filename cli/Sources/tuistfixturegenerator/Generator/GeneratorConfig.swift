import Foundation

struct GeneratorConfig {
    var projects: Int
    var targets: Int
    var sources: Int

    static var `default`: GeneratorConfig {
        GeneratorConfig(projects: 5, targets: 10, sources: 50)
    }
}
