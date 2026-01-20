---
{
  "title": "GitHub",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Learn how to integrate Tuist with GitHub for enhanced workflows."
}
---
# Integración con GitHub {#github}

Los repositorios Git son la pieza central de la gran mayoría de los proyectos de
software. Nos integramos con GitHub para ofrecer información de Tuist
directamente en tus pull requests y ahorrarte algunas configuraciones, como la
sincronización de tu rama por defecto.

## Configurar {#setup}

Tendrás que instalar la aplicación Tuist GitHub en la pestaña `Integrations` de
tu organización: {[Una imagen que muestra la pestaña de
integraciones](/images/guides/integrations/gitforge/github/integrations.png)

Después, puedes añadir una conexión de proyecto entre tu repositorio GitHub y tu
proyecto Tuist:

![Una imagen que muestra la adición de la conexión del
proyecto](/images/guides/integrations/gitforge/github/add-project-connection.png)

## Comentarios a las solicitudes de extracción/fusión {#pull-merge-request-comments}

La aplicación de GitHub publica un informe de ejecución de Tuist, que incluye un
resumen del PR, incluidos enlaces a las últimas
<LocalizedLink href="/guides/features/previews#pullmerge-request-comments">previews</LocalizedLink>
o
<LocalizedLink href="/guides/features/selective-testing#pullmerge-request-comments">tests</LocalizedLink>:

![Una imagen que muestra el comentario del pull
request](/images/guides/integrations/gitforge/github/pull-request-comment.png)

::: info REQUIREMENTS
<!-- -->
El comentario sólo se publica cuando sus ejecuciones de CI están
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticadas</LocalizedLink>.
<!-- -->
:::

::: info GITHUB_REF
<!-- -->
Si usted tiene un flujo de trabajo personalizado que no se activa en un commit
PR, pero por ejemplo, un comentario de GitHub, puede que tenga que asegurarse de
que la variable `GITHUB_REF` se establece en `refs/pull/<pr_number>/merge` o
`refs/pull/<pr_number>/head`.</pr_number></pr_number>

Puede ejecutar el comando correspondiente, como `tuist share`, con el prefijo
`GITHUB_REF` variable de entorno: <code v-pre>GITHUB_REF="refs/pull/${{
github.event.issue.number }}/head" tuist share</code>
<!-- -->
:::
