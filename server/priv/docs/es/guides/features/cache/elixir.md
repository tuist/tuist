---
title: Caché de Elixir
titleTemplate: ":title · Caché · Guías · Tuist"
description: Habilita la caché de dependencias para tu proyecto de Elixir y sigue usando Mix.
---

# Caché de Elixir

Tuist reutiliza las dependencias compiladas localmente y en las ejecuciones de CI. Actívalo una vez y sigue usando `mix compile` y `mix test`.

## Configuración

Sigue la guía <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Primeros pasos con Elixir</.localized_link> una sola vez. La configuración compartida habilita la caché de dependencias junto con el análisis de builds y tests; no hace falta configurar nada adicional para la caché.

`cache: true` selecciona automáticamente las dependencias Hex y Git compatibles; no es necesario listarlas. La compilación nativa o personalizada y las dependencias locales continúan funcionando a través de Mix con normalidad. Los archivos fuente de tu aplicación no se almacenan en caché.

## Compila como siempre

```sh
mix compile
mix test
```

Cuando una dependencia necesita compilarse, Tuist consulta primero la caché local y luego la caché remota compartida. Si no hay coincidencia, se compila con normalidad y se guarda el resultado para builds futuros. Las dependencias seleccionadas y compatibles que Mix considera actualizadas cuentan como aciertos locales cuando sus salidas compiladas están presentes y son válidas; no se requiere consultar la caché. Si la autenticación o la caché no están disponibles, Mix sigue compilando con normalidad.

## Consulta los aciertos de caché

Abre **Mix Cache** en el panel de tu proyecto para ver las tasas de acierto, las transferencias y los builds recientes. Selecciona la pestaña **Mix cache** de un build para ver qué tareas tuvieron acierto o fallo. **CAS Outputs** muestra las descargas y subidas remotas reales; los aciertos locales no generan registros de transferencia remota. Reutilizar salidas ya actualizadas contribuye a la tasa de aciertos, pero no genera bytes de transferencia, latencia de restauración ni tiempo ahorrado estimado.

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
> La compilación puede ejecutar código Elixir arbitrario. Declara entradas adicionales y excluye dependencias cuyo código dependiente del tiempo o la red, o cuyos efectos secundarios, deban ejecutarse en cada build. Los artefactos en caché pueden incluir secretos, y los escritores de caché son productores de código de confianza: no proporciones credenciales de escritura en caché a trabajos no confiables.

Para la selección de dependencias, la reutilización entre diferentes rutas de checkout, la resolución de problemas y los detalles de implementación, consulta la <.localized_link href="/guides/features/cache/elixir-advanced">configuración avanzada de la caché de Elixir</.localized_link>.
