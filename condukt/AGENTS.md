# Condukt

The independently published `condukt` Hex package lives here. Server and Atlas
use `path: "../condukt"`; keep the library's own dependencies registry-based so
external consumers do not need the monorepo.

## Development and validation

- Run Mix commands from this directory with the pinned Mise tools.
- `mix deps.get --check-locked`, `mix format --check-formatted`, `mix test`,
  `mix credo --strict`, and `mix docs` validate the library.
- Dev builds compile the Rust NIFs. For non-sandbox checks set
  `CONDUKT_BASHKIT_DISABLE=1` and `CONDUKT_MICROSANDBOX_DISABLE=1`;
  native coverage remains in the dedicated CI jobs.
- Route filesystem and command tools through `Condukt.Sandbox`, except the
  explicitly host-allowlisted `Condukt.Tools.Command` and MCP stdio transport.
  Use MuonTrap for subprocesses. Resolve secrets through `Condukt.Secrets`.
- Keep turn state in `Session.Turn`, translation in `Session.Translate`, and
  compaction in `Session.Compaction`. Preserve turn ownership and snapshot
  migrations; a crashed session must not silently restart.
- Tests must not mutate global environment/application state. Prefer async
  tests, supervised processes, and per-test temporary directories.

## Releases

- Root `.github/workflows/condukt*.yml` own CI, release, and the egress image.
  Automatic CI is path-filtered to this component and its tooling.
- Releases use `condukt@X.Y.Z` tags in `tuist/tuist`. Native download URLs and
  ExDoc source links must match that namespace and the `condukt/` source prefix.
- Build every target/NIF-version pair declared in both NIF modules. Generate
  both checksum manifests, publish the GitHub artifacts, and verify public
  downloads **before** publishing Hex. Publishing uses `MIX_ENV=prod` to test
  the precompiled path. Never publish Hex first.
- The release credentials must authorize the existing `condukt` Hex package
  and `condukt-egress` GHCR image. Repository access needs to be enabled for
  `tuist/tuist` before the first release.

## Documentation and licensing

- Library guides live in `docs/guides/` and ship as ExDoc extras; register
  new pages in `mix.exs` and keep them in the Hex package file list.
- Library, native code, and guides are MIT. Preserve the guides' own license.
- No marketing site, standalone Phoenix server, or site deployment is maintained here.
