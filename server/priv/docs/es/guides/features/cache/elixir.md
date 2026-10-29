---
title: Elixir cache
titleTemplate: ":title · Cache · Guides · Tuist"
description: Enable dependency caching for your Elixir project and keep using Mix.
---

# Caché de Elixir

Tuist reutiliza las dependencias compiladas localmente y entre compilaciones de CI. Habilítalo una vez y sigue usando `mix compile` y `mix test`.

## Configuración

Sigue <.localized_link href="/guides/get-started/elixir-project#set-up-tuist">Comenzar con Elixir</.localized_link> una vez. La configuración compartida habilita el almacenamiento en caché de dependencias junto con información sobre compilaciones y tests; no se necesita ninguna configuración adicional de caché.

`cache: true` selecciona automáticamente las dependencias Hex y Git compatibles; no es necesario enumerarlas. La compilación nativa/personalizada y las dependencias locales continúan a través de Mix normalmente. Los archivos fuente de tu aplicación no se almacenan en caché.

## Compila como de costumbre

```sh
mix compile
mix test
```

Cuando una dependencia necesita compilación, Tuist verifica la caché local y luego la caché remota compartida. Si no hay coincidencia, se compila normalmente y se almacena el resultado para futuras compilaciones. Las dependencias seleccionadas y compatibles que Mix considera actualizadas se cuentan como aciertos locales cuando sus salidas compiladas están presentes y son válidas; no es necesario buscar en la caché. Si la autenticación o la caché no están disponibles, Mix sigue compilando normalmente.

## Consulta los aciertos de tu caché

Abre **Caché de Mix** en el panel de tu proyecto para ver las tasas de aciertos, transferencias y compilaciones recientes. Selecciona la pestaña **Caché de Mix** de una compilación para ver qué tareas tuvieron aciertos o fallos. **Salidas CAS** muestra las descargas y subidas remotas reales; los aciertos locales no crean registros de transferencia remota. Reutilizar salidas ya actualizadas contribuye a la tasa de aciertos, pero no genera bytes de transferencia, latencia de restauración ni tiempo estimado ahorrado.

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
- **Deshabilitar caché:** establece `cache: false`.

> [!IMPORTANT]
> La compilación puede ejecutar código Elixir arbitrario. Declara entradas adicionales y excluye dependencias cuyo código dependiente del tiempo/red o efectos secundarios deban ejecutarse en cada compilación. Los artefactos almacenados en caché pueden incluir secretos, y los escritores de caché son productores de código de confianza: no otorgues credenciales de escritura de caché a trabajos no confiables.

Para la selección de dependencias, la reutilización entre diferentes rutas de checkout, la solución de problemas y los detalles de implementación, consulta <.localized_link href="/guides/features/cache/elixir-advanced">configuración avanzada de la caché de Elixir</.localized_link>.
