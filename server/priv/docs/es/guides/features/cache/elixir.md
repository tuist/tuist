---
title: Caché de Elixir
titleTemplate: ":title · Caché · Guías · Tuist"
description: Habilita la caché de dependencias para tu proyecto de Elixir y sigue usando Mix.
---

# Caché de Elixir

Tuist reutiliza las dependencias compiladas localmente y entre compilaciones de CI. Actívalo una vez y sigue usando `mix compile` y `mix test`.

## Configuración

Sigue <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Primeros pasos con Elixir</.localized_link> una vez. La configuración compartida habilita la caché de dependencias junto con los análisis de compilación y tests; no se necesita ninguna configuración adicional de caché.

`cache: true` selecciona automáticamente las dependencias Hex y Git compatibles; no es necesario enumerarlas. La compilación nativa/personalizada y las dependencias locales continúan a través de Mix con normalidad. Los archivos fuente de tu aplicación no se almacenan en caché.

## Compila como de costumbre

```sh
mix compile
mix test
```

Cuando una dependencia necesita compilación, Tuist comprueba la caché local y luego la caché remota compartida. Un fallo compila con normalidad y almacena el resultado para futuras compilaciones. Las dependencias seleccionadas y compatibles que Mix considera actualizadas cuentan como aciertos locales cuando sus salidas compiladas están presentes y son válidas; no se necesita ninguna búsqueda en caché. Si la autenticación o la caché no están disponibles, Mix sigue compilando con normalidad.

## Consulta tus aciertos de caché

Abre **Caché de Mix** en el panel de tu proyecto para ver las tasas de acierto, las transferencias y las compilaciones recientes. Selecciona la pestaña **Caché de Mix** de una compilación para ver qué tareas acertaron o fallaron. **Salidas CAS** muestra las descargas y subidas remotas reales; los aciertos locales no crean registros de transferencia remota. Reutilizar salidas ya actuales contribuye a la tasa de aciertos, pero no genera bytes de transferencia, latencia de restauración ni tiempo estimado ahorrado.

Para probar una restauración, limpia la salida compilada de una dependencia compatible y vuelve a compilar:

```sh
mix deps.clean nimble_options --build
mix compile
```

Reemplaza `nimble_options` por una dependencia que use tu proyecto y que ya haya poblado la caché. Mantén el mismo entorno de Mix y la misma configuración del compilador.

## Personaliza solo cuando sea necesario

La mayoría de los proyectos pueden mantener `cache: true`. Usa una lista de palabras clave para las excepciones:

```elixir
tuist: [
  project: "your-account/your-project",
  cache: [exclude: [:a_dependency_with_compile_time_side_effects]]
]
```

- **Entradas adicionales en tiempo de compilación:** declara archivos externos con `inputs: ["schemas"]` y variables de entorno con `env: ["COMPILER_OPTION"]`.
- **Solo local:** establece `remote: false`.
- **Sin subidas remotas:** establece `upload: false`. Los permisos del servidor siguen controlando el acceso.
- **Deshabilitar la caché:** establece `cache: false`.

> [!IMPORTANT]
> La compilación puede ejecutar código Elixir arbitrario. Declara entradas adicionales y excluye dependencias cuyo código dependiente del tiempo o la red, o cuyos efectos secundarios, deban ejecutarse en cada compilación. Los artefactos en caché pueden incluir secretos, y los escritores de caché son productores de código de confianza: no proporciones credenciales de escritura en caché a trabajos no confiables.

Para la selección de dependencias, la reutilización entre diferentes rutas de checkout, la resolución de problemas y los detalles de implementación, consulta <.localized_link href="/guides/features/cache/elixir-advanced">configuración avanzada de la caché de Elixir</.localized_link>.
