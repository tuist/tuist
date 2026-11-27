---
{
  "title": "Versiones",
  "titleTemplate": ":title | Colaboradores | Tuist",
  "description": "Descubre cómo funciona el proceso de publicación continua de Tuist"
}
---
# Versiones

Tuist publica nuevas versiones automáticamente cuando los cambios se fusionan en la rama principal. La CLI, el servidor y el servidor de caché Kura se distribuyen a través de canales de lanzamiento (canary, release candidate, stable) para que la instalación recomendada sea estable y cambie con poca frecuencia; la creación de una release candidate y su promoción a stable son pasos deliberados y semanales. La app se lanza de forma continua (la app de iOS solo se despliega continuamente en TestFlight; consulta más información [aquí](#app-store-release)).

## Resumen

Publicamos estos componentes principales:
- **Tuist CLI**: la herramienta de línea de comandos, distribuida a través de los [canales](#release-channels) canary, release candidate y stable
- **Tuist Server**: los servicios de backend, distribuidos mediante el mismo modelo de canales que la CLI
- **Kura**: el servidor de caché, distribuido mediante el mismo modelo de canales que la CLI
- **Tuist App**: las apps para macOS e iOS, lanzadas de forma continua (la app de iOS solo se despliega continuamente en TestFlight; consulta más información [aquí](#app-store-release))

Cada push a `main` publica una prerelease canary para la CLI, el servidor y Kura. Una versión stable de cada uno de esos componentes se crea solo cuando un mantenedor promociona una release candidate probada durante suficiente tiempo, y el calendario semanal dispara los tres trenes de lanzamiento al unísono (consulta [Canales de lanzamiento](#release-channels)). La app publica una versión stable en cada push a `main`.

## Cómo funciona

### 1. Convenciones de commits

Usamos [Conventional Commits](https://www.conventionalcommits.org/) para estructurar nuestros mensajes de commit. Esto permite que nuestras herramientas comprendan la naturaleza de los cambios, determinen los incrementos de versión y generen changelogs adecuados.

Formato: `type(scope): description`

#### Tipos de commit y su impacto

| Tipo | Descripción | Impacto en la versión | Ejemplo |
|------|-------------|----------------|---------|
| `feat` | Nueva funcionalidad o capacidad | Incremento de versión menor (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | Corrección de errores | Incremento de versión de parche (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | Cambios en la documentación | Sin lanzamiento | `docs: update installation guide` |
| `style` | Cambios de estilo de código | Sin lanzamiento | `style: format code with swiftformat` |
| `refactor` | Refactorización de código | Sin lanzamiento | `refactor(server): simplify auth logic` |
| `perf` | Mejoras de rendimiento | Incremento de versión de parche | `perf(cli): optimize dependency resolution` |
| `test` | Adiciones/cambios en tests | Sin lanzamiento | `test: add unit tests for cache` |
| `chore` | Tareas de mantenimiento | Sin lanzamiento | `chore: update dependencies` |
| `ci` | Cambios en CI/CD | Sin lanzamiento | `ci: add workflow for releases` |

Para la CLI, estos incrementos determinan la versión canary y la agrupación del changelog. Las versiones stable de la CLI son líneas menores (`X.Y.0`) creadas manualmente, y los parches stable (`X.Y.Z`) provienen únicamente de backports, por lo que un `feat` o `fix` llega a los usuarios de la CLI a través del flujo de canales descrito a continuación, en lugar de como un lanzamiento stable inmediato.

#### Cambios incompatibles

Los cambios incompatibles desencadenan un incremento de versión mayor (X.0.0) y deben indicarse en el cuerpo del commit:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Detección de cambios

Cada componente usa [git cliff](https://git-cliff.org/) para:
- Analizar los commits desde el último lanzamiento
- Filtrar los commits por ámbito (cli, app, server)
- Determinar si hay cambios listos para lanzar
- Generar changelogs automáticamente

### 3. Pipeline de lanzamiento

Cuando se detectan cambios listos para lanzar:

1. **Cálculo de versión**: El pipeline determina el siguiente número de versión
2. **Generación del changelog**: git cliff crea un changelog a partir de los mensajes de commit
3. **Proceso de compilación**: El componente se compila y prueba
4. **Generación de artefactos**: Se producen activos específicos del lanzamiento, como los bundles de la CLI, las sumas de comprobación y la especificación de la CLI `tuist.spec.json` generada a partir de `tuist --experimental-dump-help`
5. **Creación del lanzamiento**: Se crea un lanzamiento en GitHub con los artefactos
6. **Distribución**: Las actualizaciones se publican en los gestores de paquetes (por ejemplo, Homebrew para la CLI)

Para la app, esto produce un lanzamiento stable en cada merge. Para la CLI, el servidor y Kura, este mismo pipeline automático produce únicamente una prerelease **canary**; las release candidates y los lanzamientos stable se crean en el tren de lanzamiento semanal (consulta [Canales de lanzamiento](#release-channels)).

### 4. Filtrado por ámbito

Cada componente solo se lanza cuando tiene cambios relevantes:

- **CLI**: Commits con ámbito `(cli)` o sin ámbito
- **App**: Commits con ámbito `(app)`
- **Server**: Commits con ámbito `(server)`

## Canales de lanzamiento

La CLI, el servidor y Kura no se promocionan a un lanzamiento stable en cada push a `main`. Cada uno se distribuye a través de tres canales para que la instalación recomendada sea estable y cambie lentamente, mientras que los primeros adoptantes mantienen builds por commit. La documentación orientada al usuario está en <.localized_link href="/cli/release/channels">Canales de lanzamiento de la CLI</.localized_link> y <.localized_link href="/guides/server/self-host/release/channels">Canales de lanzamiento del servidor</.localized_link>; esta sección es la guía operativa para mantenedores.

Cada componente usa los mismos tres canales:

| Canal | Versión | Creado por |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | Automáticamente, en cada push a `main` que afecte al componente (`<component>-release.yml`; para Kura, lo llama `server-production-deployment.yml` cuando cambia `kura/`) |
| Release candidate | `X.Y.0-rc.N` | Cada lunes, o manualmente, en una rama `releases/<component>-<major>.<minor>.x` (`<component>-rc.yml`) |
| Stable | `X.Y.Z` | Cada lunes, o manualmente, al promocionar una RC probada durante suficiente tiempo (`<component>-promote.yml`); parches mediante `<component>-backport.yml` |

Las builds canary y RC se publican como prereleases de GitHub (nunca marcadas como "Latest", nunca mueven `:latest` en GHCR, nunca se publican en Homebrew para la CLI), por lo que los gestores de paquetes y los resolvedores de imágenes solo las toman con una opt-in explícita. Canary siempre apunta a la siguiente versión menor no lanzada: una vez creada una línea RC, la canary de `main` avanza a la siguiente versión menor.

Tuist alojado no espera al tren stable: el servidor se despliega por commit, y las instancias hosted canary y production ejecutan la última canary de Kura. La cascada de despliegue publica esa canary antes de desplegarla, por lo que `kura-release.yml` no tiene su propio trigger. Los cambios únicamente en las herramientas de lanzamiento de Kura (`mise/tasks/kura/**`, los workflows `kura-*.yml`) no generan una canary.

Nunca eliges manualmente los números de versión. La siguiente versión de cada canal se deriva de las etiquetas de git existentes mediante `mise/tasks/<component>/release/channel-version.sh`, que invocan los workflows siguientes.

Las ramas de lanzamiento están namespaced por componente (`releases/server-X.Y.x`, `releases/kura-X.Y.x`, `releases/X.Y.x` para la CLI) para que las líneas de los tres componentes nunca colisionen en la misma versión menor.

### Calendario semanal

Cada lunes a las 06:00 UTC, los trabajos de promoción de los tres componentes se ejecutan al unísono: **Promoción de la CLI a Stable**, **Promoción del servidor a Stable** y **Promoción de Kura a Stable**. Cada uno promociona la línea RC más reciente que aún no es stable, que normalmente es la línea creada el lunes anterior. Si no existe tal línea, ese trabajo no publica nada.

Cuando finaliza una promoción, independientemente del resultado, su workflow correspondiente de **Release Candidate** (`cli-rc.yml`, `server-rc.yml`, `kura-rc.yml`) se dispara mediante `workflow_run` y crea la siguiente línea desde `main`.

Si alguna ejecución programada falla o se cancela, se publica un mensaje en Slack. Una promoción falla cuando la rama de lanzamiento tiene commits posteriores a su última RC. Para lanzar esa línea, crea una nueva RC en ella y promuévela manualmente. De lo contrario, el siguiente lunes promoverá la línea más reciente.

### Crear una release candidate

Para crear una nueva línea fuera del calendario semanal (sustituye el nombre del workflow del componente a continuación):

1. Ejecuta el workflow de **\<Component\> Release Candidate** (por ejemplo, `server-rc.yml`) con una entrada `branch` vacía.
2. Publica `X.Y.0-rc.1` y, tras tener éxito, crea la rama protegida `releases/<component>-X.Y.x` en el commit compilado.

Para incorporar una corrección crítica o una regresión a una línea en fase de prueba, haz cherry-pick sobre la rama de lanzamiento mediante un PR (el mismo flujo que para los backports; la CI nunca hace cherry-pick) y luego itera la RC:

1. Crea una rama desde `releases/<component>-X.Y.x`, haz cherry-pick de la corrección, abre un PR de vuelta a la rama de lanzamiento, resuelve cualquier conflicto y haz merge.
2. Vuelve a ejecutar el workflow de **Release Candidate** con `branch=releases/<component>-X.Y.x`. Publica `X.Y.0-rc.(N+1)` desde el HEAD de la rama.

Una línea en fase de prueba está congelada en cuanto a funcionalidades: solo se incorporan correcciones críticas y regresiones.

### Promoción a stable

Para promover una línea fuera del calendario semanal, después de que su RC haya pasado la fase de prueba sin problemas:

1. Ejecuta el workflow de **\<Component\> Promote to Stable** (por ejemplo, `server-promote.yml`) con `branch=releases/<component>-X.Y.x`.
2. Publica la imagen etiquetada con semver usando `make_latest=true`, lo que mueve la etiqueta `:latest` de GHCR y el puntero "Latest" de GitHub. La CLI además actualiza la fórmula de Homebrew.

La promoción se niega a ejecutarse a menos que el HEAD de la rama sea exactamente el commit al que apunta la última RC. Por tanto, si alguna corrección se ha hecho merge en la línea después de la última RC, debes crear una nueva RC y dejarla en fase de prueba antes de que pueda lanzarse como stable.

### Backport de correcciones a una línea stable

Una vez que una línea es stable, lanza parches con el workflow exclusivo de la CLI **Backport Release** (`cli-backport.yml`): haz cherry-pick de la corrección sobre `releases/X.Y.x` mediante un PR y luego ejecuta el workflow con esa rama para crear `X.Y.(Z+1)`. Los backports nunca mueven el puntero "Latest" ni la fórmula de Homebrew. Se mantienen dos líneas a la vez: la línea actual acepta regresiones y correcciones de seguridad, mientras que la línea anterior solo acepta correcciones críticas y de seguridad. Otras correcciones de errores no se hacen backport y se lanzan con la siguiente versión menor.

Para el servidor y Kura, usa **Server Backport Release** (`server-backport.yml`) o **Kura Backport Release** (`kura-backport.yml`). La promoción publica únicamente el `X.Y.0` de una RC; no puede parchear una línea ya stable.

1. Parte de la última etiqueta stable publicada del componente en la línea `X.Y` seleccionada y abre un PR de corrección quirúrgica hacia su rama existente `releases/server-X.Y.x` o `releases/kura-X.Y.x`. Un lanzamiento menor o mayor más reciente no impide parchear una línea mantenida. Mantén fuera los cambios de main no relacionados.
2. Revisa y haz merge del PR de origen. Obtén la rama de lanzamiento remota y valida su **punta final tras el merge**, incluidas las plataformas compatibles del componente y los controles positivos/negativos de TLS. Un head pre-merge exitoso no constituye la validación de un commit squash o merge diferente.
3. Con una aprobación de publicación separada, despacha el workflow de backport correspondiente **desde main**, estableciendo `source_sha` en esa punta de merge validada exacta y `base_tag` en la etiqueta stable actual, como `server@X.Y.Z` o `kura@X.Y.Z`. El workflow deriva `X.Y.(Z+1)`; los operadores no eligen un incremento de versión menor ni promueven contenidos de canary.

La planificación actualiza la rama remota exacta y la etiqueta base, exige que el origen seleccionado coincida con la punta de la rama, rechaza un origen sin cambios o cambios fuera del componente, sus entradas de política de confianza y su validación, y fija el commit base resuelto. Los controles originados en main repiten esas comprobaciones inmediatamente antes de la publicación de la imagen versionada y en GitHub. Si la rama de origen, la base stable o la versión disponible cambian, detente y vuelve a validar en lugar de sustituir por un nuevo origen.

Los backports utilizan los publicadores multiplataforma existentes sin mover el puntero "Latest" de GitHub ni `:latest` de GHCR. La publicación es independiente del despliegue alojado: estos workflows no promocionan un servidor alojado ni la flota de Kura, no omiten la aceptación de canary ni validan un runtime instalado. Los ayudantes de build y los Dockerfiles siguen procediendo del origen stable seleccionado. Los controles son puertas de publicación, no trabajos de build sin credenciales; los builds pueden subir digests de imágenes sin etiquetar antes de la puerta final. La publicación de la imagen y en GitHub no es atómica: si la puerta posterior falla después de publicar una etiqueta de imagen, inspecciona la release parcial y conserva su origen y artefactos originales. Nunca reemplaces una release existente ni uses bytes diferentes bajo su etiqueta.

## Escribir buenos mensajes de commit

Dado que los mensajes de commit influyen directamente en las notas de la release, es importante escribir mensajes claros y descriptivos:

### Hazlo:
- Usa el presente: "add feature" en lugar de "added feature"
- Sé conciso pero descriptivo
- Incluye el alcance cuando los cambios sean específicos de un componente
- Referencia issues cuando corresponda: `fix(cli): resolve build cache issue (#1234)`

### No lo hagas:
- Uses mensajes vagos como "fix bug" o "update code"
- Mezcles múltiples cambios no relacionados en un solo commit
- Olvides incluir información sobre cambios rupturistas

### Cambios rupturistas

Para cambios rupturistas, incluye `BREAKING CHANGE:` en el cuerpo del commit:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Workflows de release

La CLI, el servidor y Kura tienen cada uno su propio conjunto de workflows de canal, siguiendo la misma estructura:

- `<component>-release.yml` - publica una canary en cada push a `main` que afecte al componente (el de Kura es un workflow reutilizable que `server-production-deployment.yml` llama cuando cambia `kura/`)
- `<component>-rc.yml` - crea una release candidate cada lunes (mediante `workflow_run` después de la promoción), o crea o itera una manualmente
- `<component>-promote.yml` - promociona la RC pendiente a stable cada lunes a las 06:00 UTC, o promociona manualmente una RC que haya pasado la fase de prueba
- `<component>-build-publish.yml` - la pipeline compartida de build y publicación que invocan los tres anteriores

La CLI, el servidor y Kura tienen además `<component>-backport.yml` para crear parches en una línea stable. Todos los workflows de un componente se serializan a través de un único grupo de concurrencia `<component>-publish` para que la resolución de versiones y el etiquetado nunca entren en conflicto. Kura es la excepción: su canary usa `kura-canary-publish` y su RC, promoción y backport usan `kura-stable-publish`, así que un build stable largo nunca retrasa la cascada de despliegue. Los espacios de nombres de las etiquetas son disjuntos, por lo que los dos grupos no pueden colisionar.

El chart de Helm y las imágenes de infraestructura (operador CAPI, controlador de runners, imagen del procesador de xcresult, imagen del runner de Linux, etc.) siguen publicándose a través de `.github/workflows/server-production-deployment.yml`. Se ejecuta en pushes a `main` y sigue la cascada canary → pruebas de aceptación → producción para el despliegue alojado, y publica esos componentes de infraestructura a medida que cambian. La app, la caché, el plugin de Gradle, las skills, Noora y los controladores de infraestructura independientes tienen cada uno un workflow dedicado `*-release.yml`. Todos comparten la detección de cambios: `mise/tasks/release/components.json` declara el prefijo de etiqueta y las rutas incluidas de cada componente, y git cliff convierte los commits coincidentes en notas de la release.

El build de la CLI (`cli-build-publish.yml`) también genera y publica un artefacto `tuist.spec.json` (generado a partir de `tuist --experimental-dump-help`) para que las herramientas downstream puedan consumir la interfaz de comandos.

## Monitorización de releases

Puedes monitorizar las releases a través de:
- [Página de GitHub Releases](https://github.com/tuist/tuist/releases)
- La pestaña de GitHub Actions para las ejecuciones de workflows
- Los archivos de changelog en el directorio de cada componente

## Beneficios

Este enfoque de release continua proporciona:

- **Entrega rápida**: Los cambios llegan a los usuarios inmediatamente después de fusionarse
- **Menos cuellos de botella**: Sin esperas para releases manuales
- **Comunicación clara**: Changelogs automatizados a partir de los mensajes de commit
- **Proceso consistente**: El mismo flujo de release para todos los componentes
- **Aseguramiento de calidad**: Solo se publican cambios probados

## Solución de problemas

Si una release falla:

1. Revisa los logs de GitHub Actions del workflow fallido
2. Asegúrate de que tus mensajes de commit sigan el formato convencional
3. Verifica que todos los tests pasen
4. Comprueba que el componente se compile correctamente

Para correcciones urgentes que necesiten una release inmediata:
1. Asegúrate de que tu commit tenga un alcance claro
2. Después de fusionar, monitoriza el workflow de release
3. Para el servidor o la app, la corrección se publica en el siguiente push; si es necesario, activa una release manual
4. Para la CLI, la corrección llega a canary automáticamente. Para que llegue a los usuarios de stable, haz backport a la(s) línea(s) stable mantenida(s) (consulta [Hacer backport de correcciones a una línea stable](#backporting-fixes-to-a-stable-line))

## Release en la App Store

Mientras que la CLI y el Server siguen el proceso de release continua descrito anteriormente, la **app de iOS** es una excepción debido al proceso de revisión de la App Store de Apple:

- **Releases manuales**: Las releases de la app de iOS requieren envío manual a la App Store
- **Retrasos en la revisión**: Cada release debe pasar por el proceso de revisión de Apple, que puede tardar entre 1 y 7 días
- **Cambios agrupados**: Múltiples cambios suelen agruparse en cada release de iOS
- **TestFlight**: Las versiones beta pueden distribuirse a través de TestFlight antes de la release en la App Store
- **Notas de la release**: Deben escribirse específicamente según las directrices de la App Store

La app de iOS sigue siguiendo las mismas convenciones de commit y usa git cliff para generar el changelog, pero la release real a los usuarios ocurre con menos frecuencia y en un calendario manual.
