# Slack (Elixir/Phoenix)

Small Phoenix app that powers the public "Join our Slack" flow and an
admin panel where an operator can manually accept invitation requests.

## Stack
- Phoenix 1.7 + LiveView
- SQLite (Ecto adapter) for persistence, mounted at `/data/slack.db` in production
- [Noora](../noora) design system for the UI
- Swoosh + gen_smtp for transactional email (confirmation links)

## Layout
- `lib/slack/` — core business logic (Repo, Invitations context, Mailer)
- `lib/slack_web/` — Phoenix router, endpoint, LiveViews, controllers
- `priv/repo/migrations/` — Ecto migrations
- `assets/` — esbuild + Tailwind sources, imports Noora CSS from `../../noora`

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
mise run dev            # (future) start phoenix server — see config/dev.exs
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
- `SMTP_RELAY`, `SMTP_USERNAME`, `SMTP_PASSWORD`, `SMTP_PORT`, `SMTP_SSL` —
  SMTP adapter configuration (Swoosh)
- `SLACK_MAILER_FROM_EMAIL`, `SLACK_MAILER_FROM_NAME` — From address
- `TURNSTILE_SITE_KEY` / `TURNSTILE_SECRET_KEY` — Cloudflare Turnstile
  credentials. `Slack.Captcha.verify/2` is called from the public
  LiveView on every submit and no-ops when the secret is blank (dev/test)

## Deployment
The app is deployed to Render via the service defined in the root
`render.yaml`. Deployments are triggered from
`.github/workflows/slack-deploy.yml` using the Render CLI (same pattern
as `server/`).
