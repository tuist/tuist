# Slack (Elixir/Phoenix)

Small Phoenix app that powers the public "Join our Slack" flow and an
admin panel where an operator can manually accept invitation requests.

## Stack
- Phoenix 1.7 + LiveView
- SQLite (Ecto adapter) for persistence, mounted at `/data/slack.db` in production
- [Noora](../noora) design system for the UI
- Swoosh + Mailgun HTTP API for confirmation and acceptance emails

## Layout
- `lib/slack/` — core business logic (Repo, Invitations context, Mailer)
- `lib/slack_web/` — Phoenix router, endpoint, LiveViews, controllers
- `priv/repo/migrations/` — Ecto migrations
- `assets/` — esbuild + Tailwind sources, imports Noora CSS from `../../noora`

## Runtime behavior
- The app runs Ecto migrations on boot unless `SKIP_MIGRATIONS=true`.
- Confirmed invitation requests can emit an internal Slack notification via `Slack.Notifier` when bot credentials are configured.
- The admin panel is protected by HTTP basic auth and intentionally returns `503` if the credentials are missing.

## Invitation lifecycle
1. Visitor submits their email and a short note on the public LiveView (`/`).
2. We create an `unconfirmed` invitation and send a Swoosh email with a
   confirmation link. Unconfirmed invitations are hidden from admins.
3. Clicking the link hits
   `GET /invitations/confirm/:token` (see
   `SlackWeb.InvitationConfirmationController`) and transitions the
   invitation to `pending`.
4. Admins authenticate with HTTP basic auth at `/admin/invitations` and
   can mark any `pending` request as `accepted`.

## Common commands
```bash
mise run install        # install elixir deps
mix phx.server          # start phoenix server locally
mise run test           # MIX_ENV=test mix test --warnings-as-errors
mise run format --check # verify formatting
mise run credo          # strict credo run
```

## Configuration (production, via `runtime.exs`)
- `DATABASE_PATH` — SQLite path, point at the mounted disk (`/data/slack.db`)
- `SECRET_KEY_BASE` — Phoenix secret
- `PHX_HOST`, `PORT`
- `SLACK_ADMIN_USERNAME` / `SLACK_ADMIN_PASSWORD` — basic auth credentials
  for the admin panel (required, or the panel returns 503)
- `SLACK_MAILER_FROM_EMAIL`, `SLACK_MAILER_FROM_NAME` — From address
- `MAILGUN_API_KEY`, `MAILGUN_DOMAIN`, `MAILGUN_BASE_URL` — Mailgun delivery settings
- `TURNSTILE_SITE_KEY` / `TURNSTILE_SECRET_KEY` — Cloudflare Turnstile
  credentials. `Slack.Captcha.verify/2` is called from the public
  LiveView on every submit and no-ops when the secret is blank (dev/test)
- `SLACK_INVITE_URL` — Shared invite URL emailed after an admin accepts a request
- `SLACK_BOT_TOKEN` / `SLACK_CHANNEL_ID` — Optional internal notification target for newly confirmed requests

## Deployment
The app is deployed to the production cluster via the standalone
`infra/helm/slack` chart and `.github/workflows/slack-deployment.yml`.
Managed-cluster secrets should come from External Secrets / 1Password rather
than being committed inline in the chart overlays.
