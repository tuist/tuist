# Standalone deployment support

- `../compose.yaml` runs PostgreSQL, a one-shot migration service, Atlas, and Caddy. Application keys and admission domain are required through `.env`; provider credentials remain optional for documentation evaluation.
- `Caddyfile` is bundled with each release. Caddy terminates encrypted browser connections; Atlas remains on the private Compose network.
- `validate.sh` exercises the built release through Compose and a disposable kind cluster, including migrations, readiness, and public documentation. It uses temporary configuration, an isolated Kubernetes configuration, and a cleanup trap. Never point it at a managed cluster.
- Set `ATLAS_SCREENSHOT_DIR` and optionally `ATLAS_CHROME_PATH` to capture desktop, mobile, and dark-theme documentation screenshots during Compose validation. Keep browser profiles temporary.
- Keep the public instructions in `../priv/docs/self-hosting.md` aligned with the files actually included in the release bundle.
