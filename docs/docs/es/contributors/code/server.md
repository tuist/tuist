---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# Servidor {#server}

Fuente:
[github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## Para qué sirve {#what-it-is-for}

El servidor alimenta las funciones del lado del servidor de Tuist, como la
autenticación, las cuentas y los proyectos, el almacenamiento en caché, los
análisis, las vistas previas, el registro y las integraciones (GitHub, Slack y
SSO). Es una aplicación Phoenix/Elixir con Postgres y ClickHouse.

::: advertencia DEPRECACIÓN TIMESCALEDB
<!-- -->
TimescaleDB está obsoleto y se eliminará. Por ahora, si lo necesita para la
configuración local o las migraciones, utilice la [documentación de instalación
de
TimescaleDB](https://docs.timescale.com/self-hosted/latest/install/installation-macos/).
<!-- -->
:::

## Cómo contribuir {#how-to-contribute}

Las contribuciones al servidor requieren la firma del CLA (`server/CLA.md`).

### Configurar localmente {#set-up-locally}

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

> [!NOTA] Los desarrolladores propios cargan secretos cifrados desde
> `priv/secrets/dev.key`. Los colaboradores externos no tendrán esa clave, y eso
> está bien. El servidor sigue funcionando localmente con
> `TUIST_SECRET_KEY_BASE`, pero OAuth, Stripe y otras integraciones permanecen
> desactivadas.

### Pruebas y formato {#tests-and-formatting}

- Pruebas: `mix test`
- Formato: `mise run format`
