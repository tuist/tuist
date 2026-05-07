# Slack (Context)

This context owns Slack app installations and reporting workflows.

## Responsibilities
- Store and manage Slack installation records for accounts.
- Generate Slack report payloads from analytics and bundle metrics.
- Deliver scheduled Slack notifications via background workers.

## Boundaries
- HTTP/API and UI code live in `server/lib/tuist_web`.
- Configuration belongs in `server/config`.
- Schema changes and migrations live in `server/priv`.

## Guardrails
- Slack installation data is customer data; update `server/data-export.md` on schema changes.

## Local end-to-end testing

Slack's OAuth redirect URI must be HTTPS, so `http://localhost:8977/integrations/slack/callback` is rejected. To exercise the real OAuth round-trip against the dev Slack app:

1. `cloudflared tunnel --url http://localhost:8977` — gives you an HTTPS URL like `https://<random>.trycloudflare.com`.
2. Edit the Tuist Slack app manifest at <https://app.slack.com/app-settings/T061C1JGAHH/A0A52HJQJ9Z/app-manifest> and set `oauth_config.redirect_urls[0]` to `https://<tunnel>.trycloudflare.com/integrations/slack/callback`.
3. In another terminal, start the server with `TUIST_SERVER_URL=https://<tunnel>.trycloudflare.com mise run dev` so `Tuist.Environment.app_url/1` (which builds the OAuth `redirect_uri`) matches the tunnel and Slack accepts the callback.
4. Hit the dashboard at the tunnel URL (cookies are origin-scoped, so logging in on `localhost:8977` won't carry over) and exercise the "Select channel" flow.

Revert the manifest's `redirect_urls` back to `https://tuist.dev/integrations/slack/callback` when you're done, and stop the tunnel. The `priv/secrets/dev.yml.enc` Slack credentials are the dev app's credentials — they're already pointed at the tunnel-via-manifest flow and don't need to be touched for this loop.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
