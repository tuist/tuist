---
{
  "title": "Instalar el paquete Hex",
  "titleTemplate": ":title · Guías · Tuist",
  "description": "Aprende a instalar y configurar el paquete Hex de Tuist en tu proyecto Elixir."
}
---
# Instala el paquete Hex {#install-the-hex-package}

Tuist ofrece un paquete de [Hex](https://hex.pm/packages/tuist_ex), `tuist_ex`, que se integra con tu proyecto Elixir para habilitar funcionalidades como <.localized_link href="/guides/features/build-insights/elixir">análisis de compilaciones</.localized_link> y <.localized_link href="/guides/features/test-insights/elixir">análisis de tests</.localized_link>. Esta guía te acompaña en la instalación y configuración.

El paquete requiere Elixir 1.18 o superior. No necesita la interfaz de línea de comandos de Tuist.

## 1. Crea el proyecto {#create-the-project}

Crea un proyecto en el panel de Tuist y elige **Mix (Elixir)** como sistema de compilación. Su identificador, `account/project`, es lo que conecta tu proyecto Mix con él.

## 2. Añade el paquete {#add-the-package}

Añade `tuist_ex` a las dependencias en tu `mix.exs`:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

Luego descárgalo:

```bash
mix deps.get
```

`runtime: false` mantiene a Tuist fuera de tu aplicación en ejecución. Continúa con <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Primeros pasos con Elixir</.localized_link> para configurar la caché, los análisis de compilaciones y los análisis de tests juntos. Las secciones siguientes cubren los detalles de autenticación y configuración.

## 3. Autentica a tu equipo y a la integración continua {#authenticate}

Cada miembro del equipo ejecuta lo siguiente para acceder a las funcionalidades de Tuist en su máquina:

```bash
mix tuist.login
```

Abre un navegador y espera a que autorices. Para iniciar sesión sin un navegador, pasa tus credenciales:

```bash
mix tuist.login --email person@example.com --password secret
```

Cuando uses un servidor de Tuist autoalojado o local, establece su URL base en `mix.exs` o pásala con `--url`:

```bash
mix tuist.login --url http://localhost:8080
```

Mantén consistente la escritura del nombre de host. Por ejemplo, una sesión guardada para `localhost` es distinta de una guardada para `127.0.0.1`.

En GitHub Actions, CircleCI y Bitrise, la integración continua no necesita un paso de inicio de sesión. La primera vez que una tarea envía un informe, intercambia el token OpenID Connect del proveedor por un token de Tuist. <.localized_link href="/guides/integrations/gitforge/github">Conecta tu repositorio de GitHub</.localized_link> a tu proyecto de Tuist y, en GitHub Actions, otorga al trabajo el permiso `id-token: write`:

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

Con cualquier otro proveedor de identidad OpenID Connect, como Fly.io Machines, configura una política de confianza de identidad de carga de trabajo en la sección **Identidades de carga de trabajo** de la página **Configuración → Autenticación** de tu cuenta, lo que concede acceso de CI a todos los proyectos actuales y futuros propiedad de esa cuenta. Establece `TUIST_OIDC_ACCOUNT` en la cuenta de Tuist propietaria del proyecto y proporciona un token de identidad recién generado con la audiencia de la política a través de `TUIST_OIDC_TOKEN`. La integración lo intercambia automáticamente cuando no hay un token de cuenta ni una sesión válida almacenada; `mix tuist.login` también lo acepta fuera de CI. Los intercambios automáticos reutilizan una sesión no caducada solo para el mismo servidor, cuenta y token de identidad proporcionado. Cambiar esa identidad desencadena un nuevo intercambio y un token de identidad vacío falla en lugar de reutilizar una sesión anterior. Las sesiones de Tuist duran una hora sin tokens de actualización, así que para cargas de trabajo de mayor duración, genera un nuevo token de identidad y ejecuta `mix tuist.login` de nuevo antes de que expire la sesión. Sigue la <.localized_link href="/guides/server/authentication#workload-identity-trust-policies">configuración de identidad de carga de trabajo</.localized_link> y el <.localized_link href="/guides/server/authentication#flyio-machines">ejemplo de Fly.io</.localized_link>.

Las solicitudes de extracción desde forks no reciben un token OpenID Connect, por lo que sus ejecuciones no se informan y siguen pasando o fallando como de costumbre. En otros proveedores, establece la variable de entorno `TUIST_TOKEN` con un token de cuenta. Sigue la <.localized_link href="/guides/integrations/continuous-integration#authentication">guía de autenticación de integración continua</.localized_link> para crear uno.

## 4. Sigue usando `mix test` y `mix compile` {#aliases}

La <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">configuración compartida</.localized_link> instala los alias de compilación y test por ti. `mix test test/my_app_test.exs:12 --trace` informa la ejecución con la misma salida y código de salida, y la integración de compilación cubre las compilaciones desencadenadas por `mix test` o `mix phx.server`. Una compilación que no encuentra nada que hacer no se informa.

Las tareas también funcionan cuando las llamas por su propio nombre. Mix inicia una tarea escrita de esa manera en el entorno `dev`, por lo que la tarea tiene que reiniciarse en un segundo proceso para el entorno de test. Añade las tareas a los entornos preferidos para evitarlo:

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
| `cache` | `boolean` o lista de palabras clave | desactivado | La configuración habilita la caché de dependencias. Consulta <.localized_link href="/guides/features/cache/elixir">caché de Elixir</.localized_link> para exclusiones e entradas adicionales. |
| `test_retries` | `integer` | `0` | Cuántas veces reintentar los tests que fallaron; consulta <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">reintentos de test</.localized_link>. |
| `tags` | lista de `String` | `[]` | Etiquetas para adjuntar a cada compilación; consulta <.localized_link href="/guides/features/build-insights/elixir#custom-metadata">metadatos personalizados</.localized_link>. |
| `values` | mapa | `%{}` | Datos clave-valor para adjuntar a cada compilación. |

Las variables de entorno tienen prioridad sobre `mix.exs`:

| Variable | Descripción |
| --- | --- |
| `TUIST_PROJECT` | El identificador del proyecto en formato `account/project`. |
| `TUIST_URL` | La URL base del servidor de Tuist. |
| `TUIST_TOKEN` | El token para autenticarse, en lugar del inicio de sesión almacenado. |
| `TUIST_OIDC_TOKEN` | Un token de identidad OpenID Connect recién generado, intercambiado por un token de Tuist. Su audiencia debe ser `tuist` para GitHub Actions y Bitrise, o coincidir con la política de confianza del proyecto para otros proveedores. Lo usa `mix tuist.login` o como alternativa cuando no hay un token de cuenta ni un inicio de sesión válido almacenado. |
| `TUIST_OIDC_ACCOUNT` | El identificador de la cuenta de Tuist propietaria del proyecto. Es necesario al intercambiar un token mediante una política de confianza del proyecto. Selecciona entre las políticas de confianza existentes y no concede acceso por sí solo. |
| `TUIST_TEST_RETRIES` | Cuántas veces reintentar los tests que fallaron. |
| `TUIST_TAGS` | Etiquetas separadas por comas para adjuntar a la compilación. |
| `TUIST_VALUES` | Pares `key=value` separados por comas para adjuntar a la compilación. |
| `TUIST_DEBUG` | Establece en `1` para imprimir el motivo por el que no se pudo enviar un informe. |

Los informes nunca cambian el código de salida de `mix test` ni de `mix compile`. Si no se puede enviar un informe, la tarea no muestra nada a menos que `TUIST_DEBUG=1` esté establecido.

## Próximos pasos {#next-steps}

Una vez instalado y configurado el paquete, puedes usar:

- <.localized_link href="/guides/features/cache/elixir">Caché de dependencias</.localized_link> para reutilizar dependencias compiladas localmente y en las compilaciones de CI.
- <.localized_link href="/guides/features/build-insights/elixir">Análisis de compilaciones</.localized_link> para rastrear tiempos de compilación, advertencias y qué ralentiza tus compilaciones.
- <.localized_link href="/guides/features/test-insights/elixir">Análisis de tests</.localized_link> para rastrear el rendimiento de los tests hasta cada test individual.
- <.localized_link href="/guides/features/test-insights/flaky-tests/elixir">Tests inestables</.localized_link> para detectar y rastrear tests que fallan intermitentemente.
- <.localized_link href="/guides/features/test-sharding/elixir">Fragmentación de tests</.localized_link> para distribuir tus tests entre ejecutores de integración continua.
