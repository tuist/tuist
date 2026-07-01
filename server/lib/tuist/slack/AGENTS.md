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

Slack's OAuth redirect URI must be HTTPS, and the URI Tuist sends to Slack is built by `Tuist.Environment.app_url/1` from `TUIST_SERVER_URL`. By default `mise/utilities/dev_instance_env.sh` exports `TUIST_SERVER_URL=http://localhost:<port>` per worktree, which Slack rejects. To exercise the real OAuth round-trip:

1. `cloudflared tunnel --url http://localhost:<your-dev-port>` — gives you an HTTPS URL like `https://<random>.trycloudflare.com`. Find your port via `echo $TUIST_SERVER_PORT` inside `mise exec`.
2. Edit the Tuist Slack app manifest at <https://app.slack.com/app-settings/T061C1JGAHH/A0A52HJQJ9Z/app-manifest> and set `oauth_config.redirect_urls[0]` to `https://<tunnel>.trycloudflare.com/integrations/slack/callback`.
3. Start the server with the tunnel URL as `TUIST_SERVER_URL`. The mise env file exports its own value, so override *after* mise sourcing — the simplest path is to bypass `mise run dev` and run the server directly:
   ```bash
   eval "$(mise env -s bash)"
   export TUIST_SERVER_URL=https://<tunnel>.trycloudflare.com
   mix phx.server
   ```
   Phoenix still binds to `127.0.0.1:$TUIST_SERVER_PORT`; cloudflared forwards from there. The OAuth `redirect_uri` Tuist hands Slack now matches the tunnel.
4. Hit the dashboard at the tunnel URL — **not** `localhost`. Session cookies are origin-scoped, so logging in on `localhost:<port>` won't carry over to the tunnel host, and the OAuth callback would land on a different origin.

Revert the manifest's `redirect_urls` back to `https://tuist.dev/integrations/slack/callback` when you're done, and stop the tunnel. The dev Slack credentials (the `SLACK` item in the 1Password `Development` vault, sourced via fnox — see `server/fnox.toml`) are the dev app's credentials — they don't need to change for this loop.

Test user creds (from the seed): `tuistrocks@tuist.dev` / `tuistrocks`. If login fails with "Invalid email or password" despite those creds, the password hash in your local DB has drifted from the seed. Reset it with the salted bcrypt the auth path expects:

```bash
mise exec -- mix run -e '
  import Ecto.Query
  Tuist.Environment.decrypt_secrets() |> Tuist.Environment.put_application_secrets()
  hash = Bcrypt.hash_pwd_salt("tuistrocks" <> Tuist.Environment.secret_key_password())
  Tuist.Repo.update_all(from(u in "users", where: u.email == "tuistrocks@tuist.dev"),
    set: [encrypted_password: hash])
'
```

The `<> secret_key_password` is required — `Tuist.Accounts.User.valid_password?/2` salts every comparison with it.

## Related Context
- Parent business logic: `server/lib/tuist/AGENTS.md`
- Web layer: `server/lib/tuist_web/AGENTS.md`
- Migrations: `server/priv/AGENTS.md`
