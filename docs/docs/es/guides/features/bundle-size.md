---
{
  "title": "Bundle insights",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Find out how to make and keep your app's memory footprint as small as possible."
}
---
# Conjunto de conocimientos {#bundle-size}

::: advertencia REQUISITOS
<!-- -->
- Una cuenta y un proyecto
  <LocalizedLink href="/guides/server/accounts-and-projects">Tuist.</LocalizedLink>
<!-- -->
:::

A medida que añades más funciones a tu aplicación, el tamaño del paquete de la
aplicación sigue creciendo. Aunque parte del aumento del tamaño del paquete es
inevitable a medida que se envían más códigos y activos, hay muchas formas de
minimizar ese crecimiento, como asegurarse de que los activos no se dupliquen en
los paquetes o eliminar los símbolos binarios que no se utilizan. Tuist te
proporciona herramientas e información para ayudarte a mantener el tamaño de tu
aplicación reducido, y también supervisamos el tamaño de tu aplicación a lo
largo del tiempo.

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
<!-- -->
:::

El comando `tuist inspect bundle` analiza el paquete y le proporciona un enlace
para ver una descripción detallada del mismo, incluyendo un escaneo del
contenido del paquete o un desglose de los módulos:

![Paquete analizado](/images/guides/features/bundle-size/analyzed-bundle.png)

## Integración continua (CI) {#continuous-integration-ci}

Para realizar un seguimiento del tamaño del paquete a lo largo del tiempo,
deberá analizar el paquete en el CI. En primer lugar, deberá asegurarse de que
su CI está
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
          TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}
```

Una vez configurado, podrás ver cómo evoluciona el tamaño de tu paquete a lo
largo del tiempo:

![Gráfico del tamaño del
paquete](/images/guides/features/bundle-size/bundle-size-graph.png)

## Comentarios sobre solicitudes de extracción/fusión {#pullmerge-request-comments}

::: warning INTEGRATION WITH GIT PLATFORM REQUIRED
<!-- -->
Para obtener comentarios automáticos de solicitudes de extracción/fusión,
integra tu <LocalizedLink href="/guides/server/accounts-and-projects">proyecto
Tuist</LocalizedLink> con una
<LocalizedLink href="/guides/server/authentication">plataforma
Git</LocalizedLink>.
<!-- -->
:::

Una vez que tu proyecto Tuist esté conectado con tu plataforma Git, como
[GitHub](https://github.com), Tuist publicará un comentario directamente en tus
solicitudes de extracción/fusión cada vez que ejecutes `tuist inspect bundle`:
![Comentario de la aplicación GitHub con paquetes
inspeccionados](/images/guides/features/bundle-size/github-app-with-bundles.png)
