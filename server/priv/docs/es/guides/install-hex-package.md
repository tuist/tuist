---
{
  "title": "Install the Hex package",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Learn how to install and configure Tuist's Hex package in your Elixir project."
}
---
# Instala el paquete Hex {#install-the-hex-package}

Tuist ofrece un paquete de [Hex](https://hex.pm/packages/tuist_ex), `tuist_ex`, que se integra con tu proyecto Elixir para habilitar funcionalidades como <.localized_link href="/guides/features/build-insights/elixir">build insights</.localized_link> y <.localized_link href="/guides/features/test-insights/elixir">test insights</.localized_link>. Esta guía te acompaña paso a paso en su instalación y configuración.

El paquete requiere Elixir 1.18 o superior. No necesita la interfaz de línea de comandos de Tuist.

## 1. Crea el proyecto {#create-the-project}

Crea un proyecto en el panel de Tuist y elige **Mix (Elixir)** como su sistema de compilación. Su identificador, `account/project`, es lo que conecta tu proyecto Mix con él.

## 2. Añade el paquete {#add-the-package}

Añade `tuist_ex` a las dependencias en tu `mix.exs`:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

Luego obténlo:

```bash
mix deps.get
```

`runtime: false` mantiene a Tuist fuera de tu aplicación en ejecución. Continúa con <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Get started with Elixir</.localized_link> para configurar conjuntamente el almacenamiento en caché, build insights y test insights. Las secciones siguientes cubren los detalles de autenticación y configuración.

## 3. Autentica a tu equipo y a la integración continua {#authenticate}

Cada miembro del equipo ejecuta lo siguiente para acceder a las funcionalidades de Tuist en su máquina:

```bash
mix tuist.login
```

Abre un navegador y espera a que autorices. Para iniciar sesión sin un navegador, proporciona tus credenciales:

```bash
mix tuist.login --email person@example.com --password secret
```

Cuando uses un servidor Tuist autoalojado o local, establece su URL base en `mix.exs` o pásala con `--url`:

```bash
mix tuist.login --url http://localhost:8080
```

Mantén consistente la escritura del nombre de host. Por ejemplo, una sesión iniciada guardada para `localhost` es independiente de una guardada para `127.0.0.1`.

En GitHub Actions, CircleCI y Bitrise, la integración continua no requiere un paso de inicio de sesión. La primera vez que una tarea envía un informe, intercambia el token OpenID Connect del proveedor por un token de Tuist. <.localized_link href="/guides/integrations/gitforge/github">Conecta tu repositorio de GitHub</.localized_link> a tu proyecto de Tuist y, en GitHub Actions, otorga al trabajo el permiso `id-token: write`:

```yaml
jobs:
  test:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix test
```

Con cualquier otro proveedor de identidad OpenID Connect, como Fly.io Machines, configura una política de confianza de identidad de carga de trabajo en la sección **Workload identities** de la página **Settings → Authentication** de tu cuenta, lo que concede acceso de CI a todos los proyectos actuales y futuros propiedad de esa cuenta. Establece `TUIST_OIDC_ACCOUNT` con la cuenta de Tuist propietaria del proyecto y proporciona un token de identidad recién generado con el público de la política a través de `TUIST_OIDC_TOKEN`. La integración lo intercambia automáticamente cuando no hay un token de cuenta ni una sesión iniciada válida almacenada; `mix tuist.login` también lo acepta fuera de CI. Los intercambios automáticos reutilizan una sesión no caducada solo para el mismo servidor, cuenta y token de identidad proporcionado. Cambiar esa identidad desencadena un nuevo intercambio y un token de identidad vacío provoca un fallo en lugar de reutilizar una sesión anterior. Las sesiones de Tuist duran una hora sin tokens de actualización, por lo que, para cargas de trabajo de mayor duración, genera un nuevo token de identidad y ejecuta `mix tuist.login` de nuevo antes de que expire la sesión. Sigue la <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">configuración de identidad de carga de trabajo</.localized_link> y el <.localized_link href="/guides/server/authentication#flyio-machines">ejemplo de Fly.io</.localized_link>.

Las solicitudes de extracción desde forks no reciben un token OpenID Connect, por lo que sus ejecuciones no se informan y siguen pasando o fallando como de costumbre. En otros proveedores, establece la variable de entorno `TUIST_TOKEN` con un token de cuenta. Sigue la <.localized_link href="/guides/integrations/continuous-integration#authentication">guía de autenticación de integración continua</.localized_link> para crear uno.

## 4. Sigue usando `mix test` y `mix compile` {#aliases}

La <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">configuración compartida</.localized_link> instala los alias de compilación y pruebas por ti. `mix test test/my_app_test.exs:12 --trace` informa de la ejecución con la misma salida y código de salida, y la integración de compilación cubre las compilaciones desencadenadas por `mix test` o `mix phx.server`. Una compilación que no encuentra nada que hacer no se informa.

Las tareas también funcionan cuando las llamas por su propio nombre. Mix inicia una tarea escrita de esa manera en el entorno `dev`, por lo que la tarea tiene que reiniciarse en un segundo proceso para el entorno de pruebas. Añade las tareas a los entornos preferidos para omitir eso:

```elixir
def cli do
  [preferred_envs: ["tuist.test": :test, "tuist.test.build": :test]]
end
```

## Referencia de configuración {#configuration-reference}

Las siguientes opciones están disponibles bajo `tuist` en las opciones del proyecto de `mix.exs`:

| Opción | Tipo | Predeterminado | Descripción |
| --- | --- | --- | --- |
| `project` | `String` | ninguno (obligatorio) | El identificador del proyecto en formato `account/project`. |
| `url` | `String` | `"https://tuist.dev"` | La URL base del servidor de Tuist. |
| `cache` | `boolean` o lista de palabras clave | deshabilitado | La configuración habilita el almacenamiento en caché de dependencias. Consulta <.localized_link href="/guides/features/cache/elixir">Elixir cache</.localized_link> para exclusiones e insumos adicionales. |
| `test_retries` | `integer` | `0` | Cuántas veces reintentar las tests que fallaron; consulta <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">test retries</.localized_link>. |
| `tags` | lista de `String` | `[]` | Etiquetas para adjuntar a cada compilación; consulta <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">custom metadata</.localized_link>. |
| `values` | mapa | `%{}` | Datos clave-valor para adjuntar a cada compilación. |

Las variables de entorno tienen prioridad sobre `mix.exs`:

| Variable | Descripción |
| --- | --- |
| `TUIST_PROJECT` | El identificador del proyecto en formato `account/project`. |
| `TUIST_URL` | La URL base del servidor de Tuist. |
| `TUIST_TOKEN` | El token para autenticarse, en lugar del inicio de sesión almacenado. |
| `TUIST_OIDC_TOKEN` | Un token de identidad OpenID Connect recién generado, intercambiado por un token de Tuist. Su audiencia debe ser `tuist` para GitHub Actions y Bitrise, o coincidir con la política de confianza del proyecto para otros proveedores. Lo utiliza `mix tuist.login` o como alternativa cuando no hay un token de cuenta ni un inicio de sesión válido almacenado disponible. |
| `TUIST_OIDC_ACCOUNT` | El identificador de la cuenta de Tuist que posee el proyecto. Es necesario al intercambiar un token a través de una política de confianza del proyecto. Selecciona entre las políticas de confianza existentes y no otorga acceso por sí solo. |
| `TUIST_TEST_RETRIES` | Cuántas veces reintentar las tests que fallaron. |
| `TUIST_TAGS` | Etiquetas separadas por comas para adjuntar a la compilación. |
| `TUIST_VALUES` | Pares `key=value` separados por comas para adjuntar a la compilación. |
| `TUIST_DEBUG` | Establece en `1` para imprimir por qué no se pudo enviar un informe. |

Los informes nunca cambian el código de salida de `mix test` o `mix compile`. Si no se puede enviar un informe, la tarea no muestra nada a menos que `TUIST_DEBUG=1` esté establecido.

## Próximos pasos {#next-steps}

Una vez que el paquete está instalado y configurado, puedes usar:

- <.localized_link href="/guides/features/cache/elixir">Almacenamiento en caché de dependencias</.localized_link> para reutilizar dependencias compiladas localmente y en las compilaciones de CI.
- <.localized_link href="/guides/features/build-insights/elixir">Build insights</.localized_link> para rastrear tiempos de compilación, advertencias y lo que ralentiza tus compilaciones.
- <.localized_link href="/guides/features/test-insights/elixir">Test insights</.localized_link> para rastrear el rendimiento de las tests hasta cada test individual.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Flaky tests</.localized_link> para detectar y rastrear tests que fallan intermitentemente.
- <.localized_link href="/guides/features/test-sharding/elixir">Test sharding</.localized_link> para dividir tus tests entre los runners de integración continua.
