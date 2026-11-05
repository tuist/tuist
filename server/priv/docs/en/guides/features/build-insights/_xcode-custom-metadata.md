## Custom metadata {#custom-metadata}

You can attach metadata to builds with environment variables to improve filtering.

### Environment variables

| Variable | Format | Description |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Comma-separated | Multiple tags in one variable. |
| `TUIST_BUILD_VALUE_*` | Single value | Key-value pair where suffix is the key. |

### Examples

Set these values in CI or your shell before invoking your build:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
