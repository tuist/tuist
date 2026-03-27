---
{
  "title": "Releases",
  "titleTemplate": ":title | Contributors | Tuist",
  "description": "Learn how Tuist's continuous release process works"
}
---
# Releases

Tuist utiliza un sistema de publicación continua que publica automáticamente
nuevas versiones cada vez que se incorporan cambios significativos a la rama
principal. Este enfoque garantiza que las mejoras lleguen rápidamente a los
usuarios sin intervención manual de los mantenedores.

## Visión general

Lanzamos continuamente tres componentes principales:
- **Tuist CLI** - La herramienta de línea de comandos
- **Tuist Server** - Los servicios backend
- **Tuist App** - Las aplicaciones macOS e iOS (la aplicación iOS sólo se
  despliega continuamente en TestFlight, más información
  [aquí](#app-store-release)

Cada componente tiene su propio proceso de publicación que se ejecuta
automáticamente cada vez que se envía a la rama principal.

## Cómo funciona

### 1. Comprometer convenios

Utilizamos [Conventional Commits](https://www.conventionalcommits.org/) para
estructurar nuestros mensajes de confirmación. Esto permite a nuestras
herramientas comprender la naturaleza de los cambios, determinar los saltos de
versión y generar los registros de cambios adecuados.

Formato: `tipo(ámbito): descripción`

#### Tipos de compromiso y su impacto

| Tipo           | Descripción                     | Versión Impacto                   | Ejemplo                                                    |
| -------------- | ------------------------------- | --------------------------------- | ---------------------------------------------------------- |
| `feat`         | Nueva función o capacidad       | Pequeño cambio de versión (x.Y.z) | `feat(cli): añadir compatibilidad con Swift 6`             |
| `fije`         | Corrección de errores           | Parche versión bump (x.y.Z)       | `fix(app): resolver el bloqueo al abrir proyectos`         |
| `docs`         | Cambios en la documentación     | Ningún comunicado                 | `docs: guía de instalación de actualizaciones`             |
| `estilo`       | Cambios en el estilo del código | Ningún comunicado                 | `estilo: formatear código con swiftformat`                 |
| `refactorizar` | Refactorización del código      | Ningún comunicado                 | `refactor(server): simplificar la lógica de autenticación` |
| `perf`         | Mejoras de rendimiento          | Aumento de la versión del parche  | `perf(cli): optimizar la resolución de dependencias`       |
| `prueba`       | Pruebas adiciones/cambios       | Ningún comunicado                 | `test: añadir pruebas unitarias para la caché`             |
| `tarea`        | Tareas de mantenimiento         | Ningún comunicado                 | `tarea: actualizar dependencias`                           |
| `ci`           | Cambios CI/CD                   | Ningún comunicado                 | `ci: añadir flujo de trabajo para liberaciones`            |

#### Cambios de última hora

Los cambios de ruptura provocan un salto de versión mayor (X.0.0) y deben
indicarse en el cuerpo de la confirmación:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Detección de cambios

Cada componente utiliza [git cliff](https://git-cliff.org/) para:
- Analizar los commits desde la última versión
- Filtrar commits por ámbito (cli, app, servidor)
- Determinar si hay cambios liberables
- Generación automática de registros de cambios

### 3. Liberación de tuberías

Cuando se detectan cambios liberables:

1. **Cálculo de la versión**: El pipeline determina el siguiente número de
   versión
2. **Changelog generation**: git cliff crea un changelog a partir de los
   mensajes de commit
3. **Proceso de construcción**: El componente se construye y se prueba
4. **Creación de versiones**: Se crea una versión GitHub con artefactos
5. **Distribución**: Las actualizaciones se envían a los gestores de paquetes
   (por ejemplo, Homebrew para CLI)

### 4. Filtrado de alcance

Cada componente sólo se libera cuando tiene cambios relevantes:

- **CLI**: Commits con alcance `(cli)` o sin alcance
- **App**: Commits con `(app)` scope
- **Servidor**: Commits con `(servidor)` ámbito

## Redactar buenos mensajes de confirmación

Dado que los mensajes de confirmación influyen directamente en las notas de
publicación, es importante escribir mensajes claros y descriptivos:

### Hazlo:
- Utiliza el presente: "añade una función", no "añade una función".
- Sea conciso pero descriptivo
- Incluir el ámbito de aplicación cuando los cambios sean específicos de un
  componente
- Cuestiones de referencia cuando proceda: `fix(cli): resolver el problema de la
  caché de compilación (#1234)`

### No lo hagas:
- Utilizar mensajes vagos como "corregir error" o "actualizar código".
- Mezclar varios cambios no relacionados en una sola confirmación
- Olvidar incluir la información sobre los cambios de última hora

### Cambios de última hora

Para cambios de última hora, incluya `BREAKING CHANGE:` en el cuerpo de la
confirmación:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Flujos de trabajo de liberación

Los flujos de trabajo de liberación se definen en:
- `.github/workflows/cli-release.yml` - Versiones CLI
- `.github/workflows/app-release.yml` - Lanzamientos de aplicaciones
- `.github/workflows/server-release.yml` - Versiones del servidor

Cada flujo de trabajo:
- Se ejecuta en empuja a la principal
- Puede activarse manualmente
- Utiliza git cliff para la detección de cambios
- Gestiona todo el proceso de liberación

## Seguimiento de las liberaciones

Puede supervisar las liberaciones a través de:
- [Página de versiones de GitHub](https://github.com/tuist/tuist/releases)
- Pestaña Acciones de GitHub para las ejecuciones del flujo de trabajo
- Archivos Changelog en cada directorio de componentes

## Beneficios

Este enfoque de liberación continua proporciona:

- **Entrega rápida**: Los cambios llegan a los usuarios inmediatamente después
  de la fusión
- **Reducción de los cuellos de botella**: No hay que esperar a las
  publicaciones manuales
- **Comunicación clara**: Registros de cambios automatizados a partir de
  mensajes de confirmación
- **Proceso coherente**: El mismo flujo de liberación para todos los componentes
- **Garantía de calidad**: Sólo se publican los cambios probados

## Solución de problemas

Si falla una liberación:

1. Comprueba los registros de acciones de GitHub para el flujo de trabajo
   fallido
2. Asegúrese de que sus mensajes de confirmación siguen el formato convencional
3. Verificar que todas las pruebas se superan
4. Compruebe que el componente se compila correctamente

Para correcciones urgentes que requieren una liberación inmediata:
1. Asegúrese de que su compromiso tiene un alcance claro
2. Tras la fusión, supervise el flujo de trabajo de liberación
3. Si es necesario, activa un desbloqueo manual

## Lanzamiento en App Store

Mientras que la CLI y el servidor siguen el proceso de publicación continua
descrito anteriormente, la aplicación **iOS** es una excepción debido al proceso
de revisión de la App Store de Apple:

- **Lanzamientos manuales**: Los lanzamientos de aplicaciones iOS requieren un
  envío manual a la App Store.
- **Retrasos en la revisión**: Cada versión debe pasar por el proceso de
  revisión de Apple, que puede tardar entre 1 y 7 días.
- **Cambios agrupados**: Los cambios múltiples suelen agruparse en cada versión
  de iOS
- **TestFlight**: Las versiones beta pueden distribuirse a través de TestFlight
  antes de su lanzamiento en el App Store.
- **Notas de la versión**: Debe estar escrito específicamente para las
  directrices de la App Store

La aplicación para iOS sigue las mismas convenciones de confirmación y utiliza
git cliff para generar el registro de cambios, pero la publicación real para los
usuarios se realiza de forma menos frecuente y manual.
