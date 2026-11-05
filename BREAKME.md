# Breaking changes worth considering in a major version.

## CLI

- Remove `tuist cache --print-hashes`. It was deprecated in favor of `tuist hash`.

## Breakme

- 11.09.2025: Drop the `cache_events` table which is no longer used.
- 05.11.2026: Change the server's `TUIST_DATABASE_SSL_VERIFY` default from `0` to `1` so database TLS verifies the server certificate and hostname. Self-hosted installs whose database uses a private CA must then set `TUIST_DATABASE_SSL_CA_CERT_FILE` or opt out with `TUIST_DATABASE_SSL_VERIFY=0`.
