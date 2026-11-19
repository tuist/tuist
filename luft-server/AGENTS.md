# Luft server

Phoenix app serving all of `luft.work`: the Luft web app (`../luft/web/`), whose Vite build the release carries in `priv/static` (Vite itself, proxied, in development), and its backend for frontend (RFC 10017) under `/api` and `/auth`. It reports to the Tuist project `tuist/luft-server`. Tuist stays the identity provider and the owner of accounts and organizations: this app signs people in as an OpenID Connect relying party of the Tuist server and calls the Tuist REST API on their behalf. It stores only sessions. See `README.md` for the contract, local setup and configuration.

## Boundaries and security

- Never trust anything about a person that did not come from a verified ID token or the Tuist API. `LuftServer.Tuist.OIDC` checks signature (RS256, provider JWKS), `iss`, `aud`, `exp` and `nonce`; keep every check.
- Tuist's access and refresh tokens stay server-side, encrypted in `sessions`; the browser only holds an opaque `HttpOnly` session cookie. Never return them in a response or log them.
- Refresh rotates Tuist's refresh token, so it runs under a row lock (`Sessions.access_token/1`); do not add a second refresh path.
- The web app and this server share one origin, so there is no CORS. Keep `LuftServerWeb.WebController`'s catch-all route last and its reserved prefixes 404ing, so an API or asset miss never returns the HTML shell. Keep the session cookie as RFC 10017 6.1.3.2 asks (`LuftServerWeb.Auth`), cookie-authenticated writes requiring this origin's `Origin` (`Plugs.RequireSameOriginWrites`), and `return_to` restricted to local paths.
- Accounts and organizations belong to Tuist. Do not copy them into this database; read and write them through `LuftServer.Tuist.API`. Tuist grants this server only the scopes it requests (`LuftServer.Tuist.OIDC`'s `@scope`), so a new Tuist capability needs a scope added to `Tuist.OAuth.Clients.luft_server_scopes/0` on the Tuist server first, then requested here; existing sessions get it at their next sign-in.
- Horizontal scaling: every replica must be interchangeable. Sessions live in PostgreSQL; the provider metadata/JWKS cache in `persistent_term` is disposable.

## Validation

Run from this directory with PostgreSQL running: `mix format --check-formatted`, `mix compile --warnings-as-errors`, `mix credo`, `mix test`. Tests stub the Tuist server with `LuftServer.FakeTuist` (`Req.Test`); never let them reach the network. Deployment is `../infra/helm/luft-server/` through `.github/workflows/luft-server-deployment.yml`.
