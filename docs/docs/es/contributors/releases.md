---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# Releases

Tuist utiliza un sistema de lanzamiento continuo que publica automáticamente
nuevas versiones cada vez que se fusionan cambios significativos en la rama
principal. Este enfoque garantiza que las mejoras lleguen rápidamente a los
usuarios sin la intervención manual de los mantenedores.

## Resumen

Publicamos continuamente tres componentes principales:
- **Tuist CLI** - La herramienta de línea de comandos.
- **Servidor Tuist** - Los servicios de backend
- **Aplicación Tuist** - Las aplicaciones para macOS e iOS (la aplicación para
  iOS solo se implementa de forma continua en TestFlight, más información
  [aquí](#app-store-release)

Cada componente tiene su propio canal de lanzamiento que se ejecuta
automáticamente cada vez que se envía algo a la rama principal.

## Cómo funciona

### 1. Convenciones de confirmación

Utilizamos [Conventional Commits](https://www.conventionalcommits.org/) para
estructurar nuestros mensajes de confirmación. Esto permite que nuestras
herramientas comprendan la naturaleza de los cambios, determinen los aumentos de
versión y generen registros de cambios adecuados.

Formato: `tipo(alcance): descripción`

#### Tipos de confirmación y su impacto

| Escribir       | Descripción                     | Impacto de la versión                    | Ejemplo                                                            |
| -------------- | ------------------------------- | ---------------------------------------- | ------------------------------------------------------------------ |
| `feat`         | Nueva función o capacidad.      | Aumento menor de la versión (x.Y.z)      | `feat(cli): añadir compatibilidad con Swift 6.`                    |
| `corregir`     | Corrección de errores.          | Aumento de la versión del parche (x.y.Z) | `fix(app): se ha solucionado el bloqueo al abrir proyectos.`       |
| `docs`         | Cambios en la documentación     | Sin publicación.                         | `docs: actualizar la guía de instalación`                          |
| `estilo`       | Cambios en el estilo del código | Sin publicación.                         | `Estilo: formatear el código con swiftformat.`                     |
| `refactorizar` | Reestructuración del código.    | Sin publicación.                         | `refactorizar (servidor): simplificar la lógica de autenticación.` |
| `perf`         | Mejoras en el rendimiento       | Aumento de la versión del parche.        | `perf(cli): optimizar la resolución de dependencias`               |
| `prueba`       | Prueba de adiciones/cambios.    | Sin publicación.                         | `Prueba: añadir pruebas unitarias para la caché.`                  |
| `tarea`        | Tareas de mantenimiento         | Sin publicación.                         | `Tarea: actualizar dependencias.`                                  |
| `ci`           | Cambios en CI/CD                | Sin publicación.                         | `ci: añadir flujo de trabajo para lanzamientos`                    |

#### Cambios importantes

Los cambios importantes provocan un aumento significativo de la versión (X.0.0)
y deben indicarse en el cuerpo del commit:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Detección de cambios

Cada componente utiliza [git cliff](https://git-cliff.org/) para:
- Analizar las confirmaciones desde la última versión.
- Filtrar las confirmaciones por ámbito (cli, app, server).
- Determina si hay cambios que se puedan publicar.
- Genera registros de cambios automáticamente.

### 3. Canalización de lanzamiento

Cuando se detectan cambios publicables:

1. **Cálculo de la versión**: El proceso determina el siguiente número de
   versión.
2. **Generación del registro de cambios**: git cliff crea un registro de cambios
   a partir de los mensajes de confirmación.
3. **Proceso de compilación**: El componente se compila y se prueba.
4. **Creación de la versión**: Se crea una versión de GitHub con artefactos.
5. **Distribución**: Las actualizaciones se envían a los gestores de paquetes
   (por ejemplo, Homebrew para CLI).

### 4. Filtrado de ámbito

Cada componente solo se publica cuando tiene cambios relevantes:

- **CLI**: Confirmaciones con `(cli)` scope o sin scope.
- **App**: Commits con `(app)` scope
- **Servidor**: Confirmaciones con `(servidor)` ámbito

## Escribir buenos mensajes de confirmación

Dado que los mensajes de confirmación influyen directamente en las notas de la
versión, es importante escribir mensajes claros y descriptivos:

### Qué hacer:
- Utilice el tiempo presente: «añadir función» en lugar de «función añadida».
- Sé conciso pero descriptivo.
- Incluye el ámbito cuando los cambios sean específicos de un componente.
- Problemas de referencia cuando sea aplicable: `fix(cli): resolver el problema
  de la caché de compilación (#1234)`

### No hagas lo siguiente:
- Utiliza mensajes vagos como «corregir error» o «actualizar código».
- Mezcla varios cambios no relacionados en una sola confirmación.
- Olvidar incluir información sobre cambios importantes.

### Cambios importantes

Para cambios importantes, incluye `BREAKING CHANGE:` en el cuerpo del commit:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Flujos de trabajo de publicación

Los flujos de trabajo de publicación se definen en:
- `.github/workflows/cli-release.yml` - Lanzamientos de CLI
- `.github/workflows/app-release.yml` - Lanzamientos de aplicaciones
- `.github/workflows/server-release.yml` - Lanzamientos del servidor

Cada flujo de trabajo:
- Se ejecuta en los envíos al principal.
- Se puede activar manualmente.
- Utiliza git cliff para la detección de cambios.
- Se encarga de todo el proceso de lanzamiento.

## Supervisión de lanzamientos

Puedes supervisar los lanzamientos a través de:
- [Página de lanzamientos de GitHub](https://github.com/tuist/tuist/releases)
- Pestaña GitHub Actions para ejecuciones de flujos de trabajo
- Archivos de registro de cambios en cada directorio de componentes.

## Ventajas

Este enfoque de lanzamiento continuo proporciona:

- **Entrega rápida**: Los cambios llegan a los usuarios inmediatamente después
  de la fusión.
- **Reducción de los cuellos de botella**: sin esperas para las liberaciones
  manuales.
- **Comunicación clara**: Registros de cambios automatizados a partir de
  mensajes de confirmación.
- **Proceso coherente**: El mismo flujo de lanzamiento para todos los
  componentes.
- **Control de calidad**: solo se publican los cambios probados.

## Solución de problemas

Si falla una publicación:

1. Comprueba los registros de GitHub Actions para ver el flujo de trabajo
   fallido.
2. Asegúrate de que tus mensajes de confirmación sigan el formato convencional.
3. Comprueba que todas las pruebas se superan.
4. Comprueba que el componente se compila correctamente.

Para correcciones urgentes que requieren una publicación inmediata:
1. Asegúrate de que tu commit tenga un alcance claro.
2. Después de la fusión, supervisa el flujo de trabajo de lanzamiento.
3. Si es necesario, activa una publicación manual.

## Lanzamiento en la App Store.

Mientras que la CLI y el servidor siguen el proceso de lanzamiento continuo
descrito anteriormente, la aplicación para iOS **** es una excepción debido al
proceso de revisión de la App Store de Apple:

- **Lanzamientos manuales**: los lanzamientos de aplicaciones iOS requieren el
  envío manual a la App Store.
- **Retrasos en la revisión**: cada lanzamiento debe pasar por el proceso de
  revisión de Apple, que puede tardar entre 1 y 7 días.
- **Cambios por lotes**: Los cambios múltiples suelen agruparse en cada versión
  de iOS.
- **TestFlight**: Las versiones beta pueden distribuirse a través de TestFlight
  antes del lanzamiento en la App Store.
- **Notas de la versión**: deben redactarse específicamente para las directrices
  de la App Store.

La aplicación para iOS sigue las mismas convenciones de compromiso y utiliza git
cliff para generar el registro de cambios, pero el lanzamiento real a los
usuarios se realiza con menos frecuencia, de forma manual.
