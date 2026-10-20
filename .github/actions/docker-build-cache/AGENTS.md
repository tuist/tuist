# Docker build cache

- Retain only BuildKit's exported OCI layer cache, never Docker credentials or a live daemon database.
- Use the released cache-volume action; leave scope, private clones, publication and cold fallback to the runner client.
- Prefer local imports when an index exists; keep the registry fallback updated.
- Export into a fresh child and rotate after a successful build. Do not replace the mounted root or accumulate unreachable blobs indefinitely.
- Local cache export is optional; preserve the previous cache if no new index was produced.
- Preserve deployment security refreshes, existing registry exports, OG cache handling and CI's Docker mirror configuration.
- Run `bash .github/actions/docker-build-cache/test.sh` and ShellCheck. Shell fixtures do not establish Docker compatibility, real publication or a performance improvement.
