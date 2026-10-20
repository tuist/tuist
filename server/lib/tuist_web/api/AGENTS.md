# Api (Web Layer)

This area owns the OpenAPI spec and schema definitions for the server API.

## Responsibilities
- `BuildEntityResources` and `Schemas.BuildEntity` define additive project-scoped native task/action/module/file endpoints. Public resource names, response keys and operation IDs are native; generic entity vocabulary is internal. Share `Tuist.BuildEntities.Params` range/cursor bounds with MCP, retain nullable measurements and history cursor metadata, and preserve old run-level ingestion/read contracts. `duration_samples` counts only measured durations (including zero), stays zero for unmeasured cohorts, and is optional in the additive public metrics schema so earlier responses remain decodable.
- `Schemas.PaginationMetadata` supports offset, cursor, and first-page offset responses that also offer cursors. Preserve optional cursor fields and page-number/total fields so existing clients can decode the first page unchanged while new clients follow cursors.
- Define the OpenAPI spec (`TuistWeb.API.Spec`) and security schemes.
- Provide schema modules used by the API controllers and docs.
- `Schemas.ReportActor` is additive response metadata. Keep provenance/source strings open for older generated clients, claims visibly unverified, and `actor` optional. Regenerate Swift contracts through `mise run generate-api-cli-code`; actor fields are server-derived, not request-body inputs. Test creation accepts optional, bounded Mix formatter runtime/custom metadata for older SDK wire compatibility without storing it or interpreting it as authorization; unsigned field allowlists must remain aligned with the declared schemas.

## Boundaries
- Domain logic belongs in `server/lib/tuist` contexts.
- Frontend assets are in `server/assets`.

## Related Context
- Web layer overview: `server/lib/tuist_web/AGENTS.md`
- Business logic: `server/lib/tuist/AGENTS.md`

- `Schemas.Builds.BuildStep` owns step properties, query parameters and errors for the three build systems. Preserve source-specific opaque ID formats and Xcode’s non-null log contract.

- `Tuist.Runners.CacheVolumes.Schemas` defines the shared public volume response and input
  contracts used by HTTP, MCP and the generated Swift client. Keep nullability,
  pagination bounds and time-range semantics aligned across all three.

- Don't declare a closed `enum` on response fields whose set of values can grow (build systems, platforms, providers). The Swift and Kotlin generators turn them into strict enums, so a new value makes every shipped client fail to decode the whole response. Use an open `:string` that documents the known values, and keep `enum` for request parameters. `Schemas.Project.build_system` is the reference case. Until clients generated from the old closed enum age out, `TuistWeb.API.ProjectsController.project_response/3` still omits `build_system` for values outside xcode, gradle and bazel.

- `Schemas.BuildMetrics` documents the shared Grafana health response across all build systems: aligned time buckets and direct whole-period totals, or bounded workload/failure rows. Preserve nullable duration/rate/cache savings fields and numeric units.
