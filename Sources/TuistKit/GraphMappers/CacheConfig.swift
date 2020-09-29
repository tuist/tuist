import TuistCore

struct CacheConfig {
    let cache: Bool
    let artifactType: ArtifactType

    static func withoutCaching() -> CacheConfig {
        CacheConfig(cache: false, artifactType: .framework)
    }

    static func withCaching(artifactType: ArtifactType = .framework) -> CacheConfig {
        CacheConfig(cache: true, artifactType: artifactType)
    }
}
