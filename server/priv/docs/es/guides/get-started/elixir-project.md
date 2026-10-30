---
{
  "title": "Proyecto Elixir",
  "titleTemplate": ":title · Primeros pasos · Guías · Tuist",
  "description": "Configura Tuist una vez para la caché de dependencias de Elixir, análisis de compilación y tests, detección de tests inestables y distribución opcional de tests."
}
---
# Proyecto Elixir {#elixir-project}

::: code-group

```text [Agent prompt]
Help me get started with Tuist. Follow the setup at:
https://tuist.dev/en/docs/guides/get-started/elixir-project
```

:::

Configura Tuist una vez y sigue usando `mix compile` y `mix test`. El paquete Hex `tuist_ex` almacena en caché las dependencias compatibles e informa de las compilaciones y ejecuciones de tests a tu panel.

## Requisitos previos

- Un proyecto Elixir construido con Mix, en Elixir 1.18 o posterior.
- Una cuenta de Tuist.

## Configurar Tuist {#set-up-tuist}

Crea un proyecto en el panel de Tuist y elige **Mix (Elixir)** como su sistema de compilación. Añade el paquete a las dependencias en tu `mix.exs`:

```elixir
defp deps do
  [
    {:tuist_ex, "~> 0.3", runtime: false}
  ]
end
```

Descárgalo, configura tu proyecto e inicia sesión:

```bash
mix deps.get
mix tuist.setup --project account/project
mix tuist.login
```

La configuración actualiza `mix.exs` con el identificador de tu proyecto, habilita la caché de dependencias e instala los alias de compilación y test. Conserva otras configuraciones y la preparación estándar de tests, como la configuración de base de datos de Phoenix. Si no puede integrar de forma segura un alias personalizado, se detiene sin modificar el archivo.

Confirma los cambios en `mix.exs` para que tu equipo y la CI utilicen la misma configuración. No hay scripts ni código de evaluación que copiar. El inicio de sesión abre un navegador; consulta <.localized_link href="/guides/install-hex-package#authenticate">autenticación</.localized_link> para el inicio de sesión sin interfaz y las credenciales de CI.

Ahora ejecuta tus comandos habituales:

```bash
mix compile
mix test
```

Las compilaciones aparecen en **Compilaciones**, las ejecuciones de tests en **Tests** y la actividad de la caché de dependencias en **Caché de Mix**. Esta es la configuración compartida para los tres. La detección de tests inestables utiliza las ejecuciones informadas; los reintentos y el sharding en CI son opcionales.

## Caché de dependencias

Tuist selecciona automáticamente las dependencias Hex y Git compatibles, sin necesidad de una lista de dependencias. Un fallo de caché compila normalmente y guarda el resultado; un acierto lo restaura. La compilación nativa/personalizada y las dependencias locales siguen gestionándose con Mix.

La compilación debe ser reproducible: declara entradas adicionales en tiempo de compilación y excluye dependencias con entradas no modeladas o efectos secundarios obligatorios. Consulta <.localized_link href="/guides/features/cache/elixir">Caché de Elixir</.localized_link> para ver las entradas compatibles, la verificación de la caché y la personalización.

## Análisis de compilaciones

Los tiempos de compilación, el grafo de dependencias entre tus archivos y cómo ambos evolucionan con el tiempo te dan lo necesario para optimizar tu grafo de compilación y aprovechar al máximo todos los núcleos disponibles en el entorno donde tiene lugar la compilación.

Con el alias `compile` configurado, Tuist informa de cada compilación: cuánto tardó, sus advertencias y errores, cuánto tardó en compilarse cada archivo y los archivos de los que depende. Abre **Compilaciones** en el panel tras tu próxima `mix compile` para verlo.

## Análisis de tests

Tuist registra el resultado y la duración de cada test en cada ejecución de `mix test`, para que puedas ver cómo evoluciona tu suite de tests con el tiempo, encontrar los tests lentos o que se han vuelto más lentos y entender por qué falló una ejecución en CI. Los encontrarás en **Tests** del panel, hasta el nivel de módulo, bloque `describe` y test.

## Tests inestables

Un test inestable pasa y falla con el mismo código. Tuist marca un test como inestable cuando falló y pasó en el mismo commit en CI. También puedes configurar el paquete para que reintente los tests que fallaron, lo que los detecta en una sola ejecución:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

Un test que pasa en un reintento se informa como inestable y la ejecución se considera exitosa. La página **Tests inestables** los enumera.

## Sharding de tests

El sharding de tests distribuye tu suite de tests entre runners de CI. Tuist equilibra los shards según el tiempo que tardó cada archivo de test en ejecuciones anteriores, compila el proyecto una vez y comparte esa compilación con cada runner. Un único comando planifica los shards:

```bash
mix tuist.test.build --shard-max 4
```

Cada runner ejecuta luego su parte con `TUIST_SHARD_INDEX` establecido, y los resultados llegan al panel como una única ejecución de tests:

```bash
TUIST_SHARD_INDEX=0 mix test
```

## Involucra al equipo

Los análisis se potencian con el número de personas conectadas al proyecto. Invita a tus compañeros a la organización desde la configuración de cuenta en el panel y configura <.localized_link href="/guides/integrations/authentication/sso">Inicio de sesión único</.localized_link> (Google, Okta, Microsoft) para que la incorporación sea un clic en lugar de un `mix tuist.login` por persona.

Para CI, no uses un inicio de sesión personal. GitHub Actions, CircleCI y Bitrise pueden autenticarse mediante OpenID Connect; en otros proveedores, establece un `TUIST_TOKEN` con ámbito limitado. Sigue los <.localized_link href="/guides/install-hex-package#authenticate">pasos de autenticación para CI</.localized_link>.
