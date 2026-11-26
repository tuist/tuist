# Luft server

Headless Phoenix server at `https://luft.work`, reporting to `tuist/luft-server`. It brokers Tuist OIDC, issues Luft native credentials and owns conversations, execution and realtime. Tuist retains identity and secret-backed capabilities. See `README.md` for endpoints, configuration and local setup.

## Boundaries and security

- Never trust anything about a person that did not come from a verified ID token or the Tuist API. `LuftServer.Tuist.OIDC` checks signature (RS256, provider JWKS), `iss`, `aud`, `exp` and `nonce`; keep every check.
- Tuist's access and refresh tokens stay server-side, encrypted in `sessions`. Boruta manages native grants bound to those session UUIDs, with Luft JWT serialization for the native account claims. Use upstream Ecto adapters with PostgreSQL-authoritative reads; retain the session lock and transaction around exchanges and refresh replay recovery in `NativeAuth`. Browsers retain opaque `HttpOnly` cookies. Never return or log Tuist tokens.
- Refresh rotates Tuist's refresh token, so it runs under a row lock (`Sessions.access_token/1`); do not add a second refresh path.
- Keep the JSON not-found catch-all last. The only frontend this server serves is the GPUI web edge (`../luft/gpui-web/`) under `/app`, which the Dockerfile builds into `priv/static/app`: its page from `WebController.app` and its listed files from `Plug.Static`, under `SecurityHeaders`' `/app` policy. Marketing pages are server-rendered here: `HomeController` serves `/` from static HTML in `lib/luft_server_web/pages/`, with a policy that allows only that page's own stylesheet by hash and no scripts; keep new pages to the same rules. Keep every other path headless; never serve Vite or the standalone `../luft/web/` sources. Preview media proxying is separate from frontend hosting.
- Keep native discovery at `/.well-known/luft.json` tied to the fixed Luft native client ID. Native authorization requires PKCE S256, state and exactly `luft://oauth-callback` or `http://127.0.0.1:<port>/callback`; reject other redirects.
- Preserve the browser cookie flow without assuming a frontend. Keep the session cookie as RFC 10017 6.1.3.2 asks (`LuftServerWeb.Auth`), cookie-authenticated writes requiring this origin's `Origin` (`Plugs.RequireSameOriginWrites`), and `return_to` restricted to local paths.
- Bind local runner credential hashes to the exact Luft session. Conversation WebSockets terminate here; never relay them to Tuist. Rewrite Tuist preview/media links to Luft, leaving object-storage URLs unchanged.
- Accounts and organizations belong to Tuist. Do not copy them into this database; read and write them through `LuftServer.Tuist.API`. Tuist grants this server only the scopes it requests (`LuftServer.Tuist.OIDC`'s `@scope`), so a new Tuist capability needs a scope added to `Tuist.OAuth.Clients.luft_server_scopes/0` on the Tuist server first, then requested here; existing sessions get it at their next sign-in.
- Horizontal scaling: every replica must be interchangeable. Sessions live in PostgreSQL; the provider metadata/JWKS cache in `persistent_term` is disposable.

## Validation

Run from this directory with PostgreSQL running: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo`, `mix test`. Tests stub the Tuist server with `LuftServer.FakeTuist` (`Req.Test`); never let them reach the network. Deployment is `../infra/helm/luft-server/` through `.github/workflows/luft-server-deployment.yml`.
