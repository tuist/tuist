# Build records and shared metadata

- Preserve existing Xcode build ingestion, processing and project-scoped authorization.
- `Metadata` defines display semantics for the existing string-valued `custom_values` map, not a new wire container or trusted identity source. Unknown keys and malformed recognized values must survive validation, storage and reads as raw metadata.
- The shared structural limit is 64 total values. Do not grant exemptions to recognized keys. Preserve tag/key/value/body limits and explicit-value precedence.
- Acceptance and advertisement are independent. `GET /api/metadata/limits` advertises 20 until `TUIST_EXPANDED_BUILD_METADATA_ENABLED` is enabled after all receivers and migrations are ready. Disable advertisement and drain in-flight submissions before downgrading.
- Observation semantics, privacy/origin constraints, rollout and remaining Once/Bazel boundaries: [build metadata](../../../docs/build-metadata.md).
- Update `server/data-export.md` for any new stored metadata category.
