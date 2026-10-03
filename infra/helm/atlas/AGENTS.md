# Atlas deployment

- `values.yaml` is the standalone contract: external PostgreSQL and an operator-provided application Secret. It must render without organization destinations, custom resource definitions, or projected Tuist server credentials.
- `values-managed-production.yaml` preserves Tuist's deployment and is passed explicitly by the managed release workflow. `.helmignore` excludes it from published archives.
- Atlas releases publish the chart and image at the same version. The chart application version selects the image unless explicitly overridden. Release publication must finish before managed deployment begins.
- Migrations use the same application Secret as the server. External databases provide `DATABASE_URL`; CloudNativePG deployments retain their generated connection Secret.
- Validate both standalone and managed rendering, chart packaging, and the Compose deployment. The public deployment guide is `atlas/priv/docs/self-hosting.md`.
- GitHub creates new registry packages as private. After the first chart publication, a package administrator must make `charts/atlas` public in package settings for anonymous registry installation. Public GitHub Release chart archives provide an installation fallback. Managed deployment authenticates to the registry.
- The application and migration container share resource settings. Cold startup exceeded the previous memory limit during standalone validation; defaults allow four gibibytes and use two Erlang schedulers. Keep sizing guidance aligned with the self-hosting guide.
