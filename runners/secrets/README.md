# Runner secrets

This directory documents the expected shape of SOPS-managed secrets for macOS runner hosts.

## Expected keys

- `xcodes-env` - newline-delimited environment variables for `xcodes`, for example Apple authentication material

## Example plaintext shape

```yaml
xcodes-env: |
  XCODES_USERNAME=apple-id@example.com
  FASTLANE_SESSION=...
```

Alternative shape if you choose direct Apple authentication:

```yaml
xcodes-env: |
  XCODES_USERNAME=apple-id@example.com
  XCODES_PASSWORD=...
```

## Recommended bootstrap

1. Convert the Mac host SSH key into an age recipient.
2. Encrypt a host-specific SOPS file.
3. Enable `tuist.runner.secrets.enable = true` on that host.
4. Point `tuist.runner.secrets.defaultSopsFile` at the encrypted file.

## Notes

- Runner registration material should be minted dynamically by the server-side GitHub integration and written to the runtime token path, not encrypted statically into the repo.
- `xcodes-env` is intended for bootstrap scripts, not for normal workflow runtime.
