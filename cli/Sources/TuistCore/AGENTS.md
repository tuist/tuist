# TuistCore

Shared domain models and run metadata. Keep command wiring and IO-heavy
HTTP/server/cache integrations in their owning feature modules, not here.

## Invariants
- Analytics types are Codable and designed for transport to the server.
- Hosted tests subtract host-provided native package products only on platforms without an explicit dynamic-linkage hint. Hints on either consumer are authoritative only for the platforms where that dependency is reachable; legacy declarations keep their existing static assumption.
- Models encode run metadata (command args, environment, git info, cache endpoints).
- `MapperEnvironment.cachedModuleSourceMappings` carries producer-to-consumer source mappings verified against the original target before binary replacement. Generation consumes only mappings for artifacts reachable in the final graph. Keep source inspection and artifact IO in TuistCache, not in the domain mapping value.
- SwiftPM exposes `CacheBudget`, `CacheCategory`, `CacheDirectoriesProvider`, and `SupportCachePruner` as the Linux-only `TuistCoreCache` target, so Cargo reuses the real shared cache lifecycle without bringing in Xcode domain models. Keep its source list and dependencies aligned with macOS. Do not expose a partial `TuistCore` on Linux: other modules use `canImport(TuistCore)` to enable Xcode-specific functionality.
- Cargo compilation entries use the shared `cargo` cache category (`Cargo/`), with 30-day retention and the support-cache byte share. Include it in the central support-cache eviction order. Its entry glob must reach individual action/blob files and staging entries below project directories, so a hot project cannot protect all historical contents from eviction. Feature modules must not create unbounded parallel cache roots.
- Restoring a test-products snapshot retains the graph, selective-testing state, and build link, but must not replay the original build's binary cache lookups as activity in each test shard.

- SDK action records, CAS blobs, and materialized XCFrameworks share the existing `binaries` category and byte budget; preserve paths already returned to generation during eviction.

- Subhash diagnostics carry optional effective destinations, foreign-build hashes, and UI-test device/runtime inputs. Missing historical inputs remain nil; RunTarget destinations retain declared graph metadata.
- External destination traversal exposes additional roots through GraphTraversing; local package test roots must have effective destinations inferred from production consumers before propagating them to test-only dependencies.
- Test automation retains the graph before test focus in MapperEnvironment so narrowing can infer local package test platforms from production consumers that focus removes.
