---
{
  "title": "Ejecutar previews con la app de macOS",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Usa la app de Tuist en la barra de menús de macOS para ejecutar previews compatibles de Apple en dispositivos y simuladores."
}
---
# Ejecuta previsualizaciones con la app de macOS

<div style="display: flex; flex-direction: column; align-items: center;">
    <img src="/logo.png" style="height: 100px;" />
    <a href="https://tuist.dev/download" style="text-decoration: none;">Download Tuist for macOS</a>
    <img src="/images/guides/features/menu-bar-app.png" style="width: 300px;" />
</div>

Para las previsualizaciones en Apple, la app de barra de menú de Tuist para macOS es una alternativa a la CLI, independientemente de si la compilación proviene de Xcode, Bazel u Once. Siguen aplicándose los requisitos de firma y elegibilidad del flujo de publicación.

## Instalar {#install}

[Descarga la app](https://tuist.dev/download) o instálala con `brew install --cask tuist/tuist/tuist`.

## Ejecutar una compilación {#run-a-build}

Selecciona un dispositivo o simulador compatible en la app de la barra de menú y luego haz clic en **Ejecutar** en la página de previsualización.

La app de macOS solicita primero la última previsualización compatible por cada app. En servidores antiguos que seleccionan apps distintas antes de aplicar filtros de plataforma, recurre al historial paginado sin imponer un límite que podría ocultar una compilación disponible.

Para el acceso y la organización, consulta <.localized_link href="/guides/features/previews#visibility">visibilidad y tracks</.localized_link>.
