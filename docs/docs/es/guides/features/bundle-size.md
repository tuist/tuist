---
{
  "title": "Bundle Size",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Tamaño del paquete {#bundle-size}

> [REQUISITOS
> - A <LocalizedLink href="/guides/server/accounts-and-projects">Cuenta tuista y
>   proyecto</LocalizedLink>

A medida que añades más funciones a tu aplicación, el tamaño del paquete sigue
creciendo. Aunque parte del crecimiento del tamaño del paquete es inevitable a
medida que envías más código y activos, hay muchas formas de minimizar ese
crecimiento, como asegurarte de que los activos no se duplican en los paquetes o
eliminar los símbolos binarios no utilizados. Tuist te proporciona herramientas
y conocimientos para ayudar a que el tamaño de tu aplicación siga siendo
pequeño, y también controlamos el tamaño de tu aplicación a lo largo del tiempo.

## Uso {#usage}

Para analizar un paquete, puede utilizar el comando `tuist inspect bundle`:

::: grupo de códigos
```bash [Analyze an .ipa]
tuist inspect bundle App.ipa
```
```bash [Analyze an .xcarchive]
tuist inspect bundle App.xcarchive
```
```bash [Analyze an app bundle]
tuist inspect bundle App.app
```
:::

El comando `tuist inspect bundle` analiza el bundle y le proporciona un enlace
para ver un resumen detallado del bundle, incluyendo un análisis del contenido
del bundle o un desglose de los módulos:

[Paquete analizado](/images/guides/features/bundle-size/analyzed-bundle.png)

## Integración continua {#continuous-integration}

Para realizar un seguimiento del tamaño del paquete a lo largo del tiempo,
deberá analizar el paquete en el CI. En primer lugar, tendrá que asegurarse de
que su CI está
<LocalizedLink href="/guides/integrations/continuous-integration#authentication">autenticado</LocalizedLink>:

Un ejemplo de flujo de trabajo para GitHub Actions podría ser el siguiente:

```yaml
name: Build

jobs:
  build:
    steps:
      - # Build your app
      - name: Analyze bundle
        run: tuist inspect bundle App.ipa
        env:
          TUIST_CONFIG_TOKEN: ${{ secrets.TUIST_CONFIG_TOKEN }}
```

Una vez configurado, podrá ver cómo evoluciona el tamaño de su paquete a lo
largo del tiempo:

[Gráfico de tamaño de
paquete](/images/guides/features/bundle-size/bundle-size-graph.png)

## Comentarios de solicitudes pull/merge {#pullmerge-request-comments}

> [IMPORTANTE] INTEGRACIÓN CON PLATAFORMA GIT REQUERIDA Para obtener comentarios
> automáticos en las solicitudes pull/merge, integra tu proyecto
> <LocalizedLink href="/guides/server/accounts-and-projects">Tuist</LocalizedLink>
> con una plataforma
> <LocalizedLink href="/guides/server/authentication">Git</LocalizedLink>.

Una vez que tu proyecto Tuist esté conectado con tu plataforma Git como
[GitHub](https://github.com), Tuist publicará un comentario directamente en tus
pull/merge requests cada vez que ejecutes `tuist inspect bundle`: ![GitHub app
comment with inspected
bundles](/images/guides/features/bundle-size/github-app-with-bundles.png)
