# Slack invitation app

Phoenix/LiveView with SQLite (`/data/slack.db` in production), Noora, and
Swoosh/Mailgun. Run from `slack/`:

```bash
mise run install
mix phx.server
mise run test
mise run format --check
mise run credo
```

## Constraints

- Invitation lifecycle: `unconfirmed` → email confirmation → `pending` → admin
  acceptance → `accepted`. Hide unconfirmed requests from admins.
- `/admin/invitations` uses HTTP basic auth and must return `503` when admin
  credentials are missing.
- `Slack.Captcha.verify/2` checks every public submission. A blank Turnstile
  secret bypasses verification for dev/test.
- Migrations run on boot unless `SKIP_MIGRATIONS=true`. Keep the SQLite volume
  persistent; configuration is defined in `config/runtime.exs`.
- Deploy independently with `infra/helm/slack/` and
  `.github/workflows/slack-deployment.yml`. Managed secrets come from External
  Secrets/1Password, not inline chart values.
