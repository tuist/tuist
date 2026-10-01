# Api (Web Layer)

This area owns the OpenAPI spec and schema definitions for the server API.

## Responsibilities
- Define the OpenAPI spec (`TuistWeb.API.Spec`) and security schemes.
- Provide schema modules used by the API controllers and docs.

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

- Don't declare a closed `enum` on response fields whose set of values can grow (build systems, platforms, providers). The Swift and Kotlin generators turn them into strict enums, so a new value makes every shipped client fail to decode the whole response. Use an open `:string` that documents the known values, and keep `enum` for request parameters. `Schemas.Project.build_system` is the reference case.
