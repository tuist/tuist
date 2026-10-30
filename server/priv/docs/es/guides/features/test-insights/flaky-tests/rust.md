---
{
  "title": "Tests inestables en Rust",
  "titleTemplate": ":title · Tests inestables · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta e investiga tests inestables de Cargo usando el historial de CI."
}
---
# Tests inestables en Rust {#rust-flaky-tests}

Tuist puede detectar resultados inconsistentes de los tests de Cargo y ayudarte a investigarlos en **Tests → Flaky Tests**.

> [!IMPORTANT] Requirements
> - Configura <.localized_link href="/guides/features/test-insights/rust">Análisis de tests para Rust</.localized_link>.

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist compara ejecuciones de CI en el mismo commit. Un test que pasa en una ejecución y falla en otra puede marcarse como inestable.

Informa cada ejecución mediante el comando habitual:

```sh
tuist cargo test --workspace
```

Cargo no reintenta automáticamente los tests fallidos. Volver a ejecutar un trabajo de CI en el mismo commit proporciona otro resultado para la detección entre ejecuciones.

## Gestión de tests inestables {#managing-flaky-tests}

### Limpieza automática

La detección y la recuperación se ejecutan a través de la automatización «Detección de tests inestables» del proyecto. De forma predeterminada, la marca de inestabilidad se limpia tras 14 días sin volver a activarse. Edita la ventana de recuperación y las acciones en **Settings → Automations**.

### Gestión manual

Abre **Tests → Flaky Tests** para inspeccionar el historial de un test. Puedes marcarlo o desmarcarlo manualmente como inestable desde su página de detalles.

## Cuarentena y pruebas de estrés {#quarantine}

Silencia u omite un test desde su página de detalles, o configura la cuarentena en **Settings → Automations**. La siguiente ejecución de `tuist cargo test` obtiene el estado actual de cuarentena del proyecto:

- Los tests **Silenciados** siguen ejecutándose e informan de sus resultados reales, pero sus fallos no hacen fallar el comando. Otros fallos de tests, errores de compilación, cierres inesperados y resultados incompletos siguen fallando con normalidad.
- Los tests **Omitidos** se excluyen de la ejecución y se informan como omisiones en cuarentena. La coincidencia incluye el paquete, el target, la ruta del módulo de Rust y el nombre del test, por lo que tests con nombres similares permanecen independientes.

El silenciamiento preserva los paquetes y las funcionalidades seleccionadas del workspace y ejecuta todos los targets seleccionados incluso si un target silenciado falla. La cuarentena por omisión requiere un único paquete seleccionado: usa `tuist cargo test -p store` en lugar de un comando de workspace con varios paquetes. Tuist rechaza la omisión con varios paquetes porque reducir el alcance del comando puede cambiar las funcionalidades unificadas de las dependencias de Cargo.

La cuarentena también se aplica a <.localized_link href="/guides/features/test-sharding/rust">ejecuciones fragmentadas de Cargo</.localized_link>. Si Tuist no puede obtener el estado, muestra una advertencia y se ejecuta sin cuarentena; los fallos no se suprimen. Para ejecutar deliberadamente sin cuarentena:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

La aplicación requiere harnesses estándar de libtest y la captura de la salida predeterminada. Los comandos con salida silenciosa, detallada, en formato alternativo o sin capturar fallan cuando es necesario aplicar la cuarentena. Selecciona un paquete exacto del workspace con `-p <package>` si la atribución al target es ambigua. No se admiten harnesses personalizados, patrones glob para nombres de paquete/target ni selecciones de paquetes sin resolver. Los doctests también pueden silenciarse u omitirse, pero el filtrado de tests de Rustdoc no puede distinguir todas las parejas posibles de nombres de ejemplos. Si omitir un ejemplo también omitiría un ejemplo habilitado, o una exclusión parcial de doctest usa `--exact`, Tuist falla con un diagnóstico en lugar de ejecutar el ejemplo omitido u omitir silenciosamente tests habilitados; usa la anulación anterior mientras investigas.

Tuist no realiza pruebas de estrés de nuevos tests de Cargo. Usa un filtro de tests de Cargo para repetir un test que falla mientras lo investigas:

```sh
tuist cargo test -p store rejects_invalid_token
```

## Notificaciones de Slack {#notifications}

Configura <.localized_link href="/guides/integrations/slack#flaky-test-alerts">alertas de tests inestables en Slack</.localized_link> para notificar a tu equipo cuando un test se vuelve inestable.
