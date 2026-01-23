---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# Serwer {#server}

Źródło:
[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## Do czego służy {#what-it-is-for}

Serwer obsługuje funkcje po stronie serwera Tuist, takie jak uwierzytelnianie,
konta i projekty, pamięć podręczna, statystyki, podglądy, rejestr i integracje
(GitHub, Slack i SSO). Jest to aplikacja Phoenix/Elixir z Postgres i ClickHouse.

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB jest przestarzałe i zostanie usunięte. Na razie, jeśli potrzebujesz
go do lokalnej konfiguracji lub migracji, skorzystaj z [dokumentacji
instalacyjnej
TimescaleDB](https://docs.timescale.com/self-hosted/latest/install/installation-macos/).
<!-- -->
:::

## Jak wnieść swój wkład {#how-to-contribute}

Aby móc wnosić wkład do serwera, należy podpisać umowę CLA (`server/CLA.md`).

### Skonfiguruj lokalnie {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Minimal secrets
export TUIST_SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

> [!UWAGA] Deweloperzy pierwotni ładują zaszyfrowane sekrety z
> `priv/secrets/dev.key`. Zewnętrzni współpracownicy nie będą mieli tego klucza
> i nie ma w tym nic złego. Serwer nadal działa lokalnie z
> `TUIST_SECRET_KEY_BASE`, ale OAuth, Stripe i inne integracje pozostają
> wyłączone.

### Testy i formatowanie {#tests-and-formatting}

- Testy: `test mieszany`
- Format: `mise run format`
