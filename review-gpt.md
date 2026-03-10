# Review

Reviewed `jj diff -r @-` for `cschmatzler/fix-kv-explosion`.

## Findings

- Medium: `cache/lib/cache/s3.ex:68` falls back to the legacy cache bucket whenever `head_object_exists?/2` returns `false`, but `cache/lib/cache/s3.ex:447` currently returns `false` for every error, not just `404`s. A transient timeout / `429` / `5xx` from `S3_CAS_BUCKET` will now generate a presigned URL for `S3_BUCKET` even when the artifact only exists in the primary CAS bucket, turning a temporary S3 issue into a user-visible miss. The fallback should only trigger on a definite not-found response and propagate or retry other failures.
