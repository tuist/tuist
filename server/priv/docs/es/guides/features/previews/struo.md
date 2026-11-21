---
{
  "title": "Previsualizaciones de Struo",
  "titleTemplate": ":title · Previews · Tuist",
  "description": "Publica previsualizaciones de aplicaciones para Android, el simulador de Apple y macOS a través del proveedor nativo de Tuist de Struo."
}
---
# Previews de Struo {#struo-previews}

<a id="once-previews"></a>

[Struo](https://struo.run/docs/guide/infrastructure/tuist#publish-application-previews) puede publicar artefactos de aplicación en Tuist para que tus compañeros puedan probar una compilación sin tener que recompilarla localmente. Usa [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) o una versión posterior y un servidor de Tuist con el receptor de artefactos.

## Configurar el destino

Completa <.localized_link href="/guides/get-started/struo-project">Primeros pasos con Struo</.localized_link> y luego añade la vinculación de artefactos en el `struo.toml` del espacio de trabajo. Reutiliza el proveedor si ya está configurado para la caché:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.artifacts]
name = "tuist"
```

```bash
struo auth login --provider tuist
struo artifact publish MyApplication --track review
```

El receptor conserva el conjunto completo, los manifiestos de los miembros y las cargas útiles, incluidas las interfaces desconocidas. Las interfaces nativas compatibles se proyectan de forma asíncrona en las previews usando la visibilidad, el acceso y la distribución predeterminados del proyecto. El contenido genérico de los artefactos permanece privado, incluso en proyectos públicos. Un recibo confirma el almacenamiento del artefacto, no la finalización del procesamiento de la preview; su URL abre la lista de previews del proyecto.

## Aplicaciones elegibles

La proyección de Apple acepta los metadatos `dev.struo.apple-install.v2` para aplicaciones de macOS y del simulador firmadas ad-hoc exportadas en macOS. Las aplicaciones para dispositivos físicos no son elegibles. La proyección de Android acepta los metadatos `dev.struo.android-install.v1` con una firma verificada. Struo aprueba la publicación automática solo para APKs firmados en modo debug y sin instrumentación. Las interfaces desconocidas siguen siendo descargables como artefactos sin crear previews. Los enlaces de instalación de Android conservan un nombre de archivo `.apk` aunque las cargas útiles se almacenen bajo resúmenes de contenido.

## Activar la publicación después de las compilaciones

```toml
[infrastructure]
publish_on_build = ["MyApplication"]
```

```bash
struo artifact publish MyApplication --allow-on-build
struo build MyApplication
```

Todas las compilaciones solicitadas deben completarse con éxito. La publicación automática también requiere la aprobación del productor de todo el cierre y la autorización local para esta máquina, espacio de trabajo, endpoint exacto, destino y destino estable del proyecto de Tuist. Sin política ni autorización, no se realizan solicitudes de red para la publicación de artefactos. Las compilaciones ordinarias de Struo permanecen libres de efectos secundarios implícitos de publicación.

Volver a ejecutar la misma publicación retenida verifica el recibo remoto y evita otra subida. Esto difiere del comportamiento de compilación duplicada de `tuist share`.

## Retención

Las publicaciones de artefactos caducan después de 30 días en Tuist alojado. Las instancias autoalojadas usan `TUIST_APP_PREVIEW_RETENTION_DAYS`; dejarlo sin configurar desactiva la caducidad para esta familia. Los registros caducados permanecen como tumbas y no pueden reactivarse volviendo a ejecutar la misma intención. Los flujos de trabajo existentes de firma, visibilidad y distribución de `tuist share` permanecen sin cambios.

Consulta <.localized_link href="/guides/features/previews#run-a-preview">Ejecutar una preview</.localized_link> para ejecutar compilaciones publicadas, gestionar el acceso, las tracks y las insignias de README.

## Previews de Apple

Para las previews elegibles del simulador de Apple y de macOS, consulta las <.localized_link href="/guides/features/previews/run/macos">instrucciones de la app complementaria de Tuist para macOS</.localized_link>. Las aplicaciones para dispositivos físicos siguen sin ser elegibles para la publicación con Struo.
