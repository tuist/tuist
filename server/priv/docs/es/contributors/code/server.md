---
{
  "title": "Servidor",
  "titleTemplate": ":title · Código · Colaboradores · Tuist",
  "description": "Contribuye al servidor de Tuist."
}
---
# Servidor {#server}

Fuente: [github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## Para qué sirve {#what-it-is-for}

El servidor impulsa las funcionalidades del lado del servidor de Tuist, como la autenticación, las cuentas y los proyectos, el almacenamiento en caché, los insights, las previews, el registry y las integraciones (GitHub, Slack y SSO). Es una aplicación Phoenix/Elixir con Postgres y ClickHouse.

## Cómo contribuir {#how-to-contribute}

Las contribuciones al servidor requieren firmar el CLA (`server/CLA.md`).

### Configuración local {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

Abre `http://localhost:8080` en tu navegador. En desarrollo, la página de inicio de sesión incluye un botón **Iniciar sesión como usuario de prueba** que te conecta con la cuenta preconfigurada (`tuistrocks@tuist.dev` / `tuistrocks`).

> [!NOTE]
> Los desarrolladores internos cargan los secretos de desarrollo desde 1Password mediante fnox: `mise run dev` envuelve el servidor en `fnox exec` (consulta `server/fnox.toml`). Los colaboradores externos no necesitan acceso a 1Password; el servidor se ejecuta localmente sin él. OAuth, Stripe y otras integraciones de terceros estarán deshabilitadas, pero la funcionalidad principal funciona.

### Pruebas locales con Helm {#local-helm-testing}

Puedes desplegar toda la pila en tu máquina usando [kind](https://kind.sigs.k8s.io/) y las tareas de mise incluidas. Esto construye las imágenes de Docker localmente, crea un clúster de kind, instala el chart y redirige los puertos de todos los servicios automáticamente:

```bash
# Deploy everything (builds images from source)
mise run helm:up --license "YOUR_LICENSE_KEY"

# Include the observability stack (Grafana, Prometheus, Loki, Tempo)
mise run helm:up --license "YOUR_LICENSE_KEY" --observability

# Check status
mise run helm:status

# Tear down
mise run helm:down
```

**Requisitos previos:** `docker`, `kind`, `helm` y `kubectl`.

### Tests y formato {#tests-and-formatting}

- Tests: `mix test`
- Formato: `mise run format`
