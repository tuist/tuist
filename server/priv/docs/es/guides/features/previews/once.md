---
{
  "title": "Publicación de artefactos Once",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Publica artefactos inmutables de la aplicación Once en un proyecto de Tuist existente con autorización explícita del destino."
}
---
# Publicación de artefactos con Once

[Once](https://buildonce.dev/docs/guide/infrastructure/tuist#publish-application-previews) puede publicar artefactos inmutables usando la autenticación existente de Tuist. Esto requiere Once 0.74.0+ y un servidor de Tuist con el receptor de artefactos. Once 0.73.x usa en su lugar el adaptador heredado de carga única.

## Configurar el destino

En el `once.toml` del espacio de trabajo:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
once auth login --provider tuist
once artifact publish MyApplication --track review
```

El receptor conserva el conjunto completo, los manifiestos de los miembros y las cargas útiles, incluidas las interfaces desconocidas. Las interfaces nativas compatibles se proyectan de forma asíncrona en las previsualizaciones usando la visibilidad, el acceso y la distribución predeterminados del proyecto. El contenido genérico de los artefactos permanece privado, incluso en proyectos públicos. Un recibo confirma el almacenamiento del artefacto, no la finalización del procesamiento de la previsualización; su URL abre la lista de previsualizaciones del proyecto.

## Aplicaciones elegibles

La proyección para Apple acepta los metadatos `dev.once.apple-install.v2` para aplicaciones de macOS y del simulador firmadas de forma ad-hoc exportadas en macOS. Las aplicaciones para dispositivos físicos no son elegibles. La proyección para Android acepta los metadatos `dev.once.android-install.v1` con una firma verificada. Once aprueba la publicación automática solo para APKs firmados en modo debug y sin instrumentación. Las interfaces desconocidas siguen siendo descargables como artefactos sin crear previsualizaciones. Los enlaces de instalación de Android conservan un nombre de archivo `.apk` aunque las cargas útiles se almacenen bajo resúmenes de contenido.

## Activar la publicación después de las compilaciones

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
once artifact publish MyApplication --allow-on-build
once build MyApplication
```

Todas las compilaciones solicitadas deben completarse con éxito. La publicación automática también requiere la aprobación del productor de todo el cierre y la autorización local para esta máquina, espacio de trabajo, extremo exacto, destino y destino estable del proyecto de Tuist. Sin política ni autorización, no se realizan solicitudes de red para la publicación de artefactos. Las compilaciones ordinarias de Once permanecen libres de efectos secundarios implícitos de publicación.

Volver a ejecutar la misma publicación retenida verifica el recibo remoto y evita otra subida. Esto difiere del comportamiento de compilación duplicada de `tuist share`.

## Retención

Las publicaciones de artefactos caducan después de 30 días en Tuist alojado. Las instancias autoalojadas usan `TUIST_APP_PREVIEW_RETENTION_DAYS`; dejarlo sin configurar desactiva la caducidad para esta familia. Los registros caducados permanecen como marcadores de eliminación y no pueden reactivarse volviendo a ejecutar la misma intención. Los flujos de trabajo existentes de firma, visibilidad y distribución de `tuist share` permanecen sin cambios.

Consulta <.localized_link href="/guides/features/previews#run-a-preview">Ejecutar una previsualización</.localized_link> para ejecutar compilaciones publicadas, gestionar el acceso, los canales y las insignias de README.

## Previsualizaciones de Apple

Para las previsualizaciones elegibles del simulador de Apple y de macOS, consulta las <.localized_link href="/guides/features/previews/run/macos">instrucciones de la aplicación complementaria de Tuist para macOS</.localized_link>. Las aplicaciones para dispositivos físicos siguen sin ser elegibles para la publicación con Once.
