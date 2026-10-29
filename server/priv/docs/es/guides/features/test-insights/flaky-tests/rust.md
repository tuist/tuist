---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# Tests inestables de Rust {#rust-flaky-tests}

Tuist puede detectar resultados inconsistentes de las pruebas de Cargo y ayudarte a investigarlos en **Tests → Flaky Tests**.

> [!IMPORTANT] Requirements
> - Configura <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>.

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist compara ejecuciones de CI en el mismo commit. Una prueba que pasa en una ejecución y falla en otra puede marcarse como inestable.

Reporta cada ejecución mediante el comando habitual:

```sh
tuist cargo test --workspace
```

Cargo no reintenta automáticamente las pruebas fallidas. Volver a ejecutar un trabajo de CI en el mismo commit proporciona otro resultado para la detección entre ejecuciones.

## Gestión de tests inestables {#managing-flaky-tests}

### Limpieza automática

La detección y la recuperación se ejecutan a través de la automatización "Flaky test detection" del proyecto. Por defecto, la marca de inestabilidad se limpia después de 14 días sin volver a activarse. Edita la ventana de recuperación y las acciones en **Settings → Automations**.

### Gestión manual

Abre **Tests → Flaky Tests** para inspeccionar el historial de una prueba. Puedes marcarla o desmarcarla manualmente como inestable desde su página de detalles.

## Cuarentena y pruebas de estrés {#quarantine}

Silencia u omite una prueba desde su página de detalles, o configura la cuarentena en **Settings → Automations**. El siguiente `tuist cargo test` obtiene el estado actual de cuarentena del proyecto:

- Las pruebas **Muted** siguen ejecutándose y reportan sus resultados reales, pero sus fallos no hacen fallar el comando. Otros fallos de pruebas, errores de compilación, bloqueos y resultados incompletos siguen fallando normalmente.
- Las pruebas **Skipped** se excluyen de la ejecución y se reportan como omisiones en cuarentena. La coincidencia incluye el paquete, el target, la ruta del módulo de Rust y el nombre de la prueba, por lo que las pruebas con nombres similares permanecen independientes.

El silenciamiento preserva los paquetes y funcionalidades seleccionados del workspace, y ejecuta todos los targets seleccionados incluso después de que falle un target silenciado. La cuarentena de omisión requiere un paquete seleccionado: usa `tuist cargo test -p store` en lugar de un comando de workspace de múltiples paquetes. Tuist rechaza la omisión de múltiples paquetes porque reducir el comando puede cambiar las funcionalidades unificadas de dependencias de Cargo.

La cuarentena también se aplica a <.localized_link href="/guides/features/test-sharding/rust">sharded Cargo runs</.localized_link>. Si Tuist no puede obtener el estado, muestra una advertencia y se ejecuta sin cuarentena; los fallos no se suprimen. Para ejecutar deliberadamente sin cuarentena:

```sh
TUIST_TEST_SKIP_QUARANTINE=1 tuist cargo test --workspace
```

La aplicación requiere harnesses estándar de libtest y la captura de la salida predeterminada. Los comandos con salida silenciosa, detallada, en formato alternativo o no capturada fallan cuando es necesario aplicar la cuarentena. Selecciona un paquete exacto del workspace con `-p <package>` si la atribución del target es ambigua. Los harnesses personalizados, los patrones glob de nombre de paquete/target y las selecciones de paquete no resueltas no son compatibles. Las doctests también pueden silenciarse u omitirse, pero el filtrado de pruebas de Rustdoc no puede distinguir cada posible par de nombres de ejemplos. Si omitir un ejemplo también omitiría un ejemplo habilitado, o una exclusión parcial de doctest usa `--exact`, Tuist falla con un diagnóstico en lugar de ejecutar el ejemplo omitido u omitir silenciosamente las pruebas habilitadas; usa la anulación anterior mientras investigas.

Tuist no realiza pruebas de estrés en nuevas pruebas de Cargo. Usa un filtro de pruebas de Cargo para repetir una prueba que falla mientras la investigas:

```sh
tuist cargo test -p store rejects_invalid_token
```

## Notificaciones de Slack {#notifications}

Configura <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link> para notificar a tu equipo cuando una prueba se vuelva inestable.
