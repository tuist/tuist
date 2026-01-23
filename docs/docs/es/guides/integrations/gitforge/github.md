---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# Integración con GitHub {#github}

Los repositorios Git son el eje central de la gran mayoría de los proyectos de
software que existen. Nos integramos con GitHub para proporcionar información de
Tuist directamente en tus solicitudes de extracción y para ahorrarte algunas
configuraciones, como la sincronización de tu rama predeterminada.

## Configuración {#setup}

Deberá instalar la aplicación Tuist GitHub en la pestaña Integraciones` de su
organización en `: ![Una imagen que muestra la pestaña de
integraciones](/images/guides/integrations/gitforge/github/integrations.png)

Después, puedes añadir una conexión de proyecto entre tu repositorio GitHub y tu
proyecto Tuist:

![Imagen que muestra cómo añadir la conexión del
proyecto](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Comentarios sobre solicitudes de extracción/fusión {#pull-merge-request-comments}

La aplicación GitHub publica un informe de ejecución de Tuist, que incluye un
resumen de la PR, con enlaces a las últimas
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">previsualizaciones</LocalizedLink>
o
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">pruebas</LocalizedLink>:

![Imagen que muestra el comentario de la solicitud de
extracción](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
El comentario solo se publica cuando tus ejecuciones de CI están
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticadas</LocalizedLink>.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
Si tienes un flujo de trabajo personalizado que no se activa con una
confirmación de PR, sino, por ejemplo, con un comentario de GitHub, es posible
que debas asegurarte de que la variable `GITHUB_REF` esté configurada como
`refs/pull/<pr_number>/merge` o
`refs/pull/<pr_number>/head`.</pr_number></pr_number>

Puede ejecutar el comando correspondiente, como `tuist share`, con el prefijo
`GITHUB_REF` variable de entorno: <code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
