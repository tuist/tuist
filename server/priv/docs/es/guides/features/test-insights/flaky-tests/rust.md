---
{
  "title": "Rust Flaky Tests",
  "titleTemplate": ":title · Flaky Tests · Test Insights · Features · Guides · Tuist",
  "description": "Detect and investigate flaky Cargo tests using CI history."
}
---
# tests inestables de Rust {#rust-flaky-tests}

Tuist puede detectar resultados inconsistentes de tests de Cargo y ayudarte a investigarlos en **Tests → Flaky Tests**.

> [!IMPORTANT] Requirements
> - Configura <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>.

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist compara ejecuciones de CI en el mismo commit. Un test que pasa en una ejecución y falla en otra puede marcarse como inestable.

Reporta cada ejecución mediante el comando habitual:

```sh
tuist cargo test --workspace
```

Cargo no reintenta automáticamente los tests fallidos. Volver a ejecutar un trabajo de CI en el mismo commit proporciona otro resultado para la detección entre ejecuciones.

## Gestión de tests inestables {#managing-flaky-tests}

### Limpieza automática

La detección y recuperación se ejecutan a través de la automatización "Flaky test detection" del proyecto. Por defecto, la marca de inestable se limpia después de 14 días sin volver a activarse. Edita la ventana de recuperación y las acciones en **Settings → Automations**.

### Gestión manual

Abre **Tests → Flaky Tests** para inspeccionar el historial de un test. Puedes marcarlo o desmarcarlo manualmente como inestable desde su página de detalles.

## Cuarentena y pruebas de estrés {#quarantine}

La integración con Cargo aún no aplica cuarentena: los tests silenciados u omitidos en el dashboard siguen ejecutándose y sus fallos siguen afectando al resultado. Tampoco realiza pruebas de estrés en nuevos tests. Usa un filtro de test de Cargo para repetir un test fallido mientras lo investigas:

```sh
tuist cargo test -p store rejects_invalid_token
```

## Notificaciones de Slack {#notifications}

Configura <.localized_link href="/guides/integrations/slack#flaky-test-alerts">Slack flaky test alerts</.localized_link> para notificar a tu equipo cuando un test se vuelva inestable.
