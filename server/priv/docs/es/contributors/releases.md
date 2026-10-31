---
{
  "title": "Versiones",
  "titleTemplate": ":title | Colaboradores | Tuist",
  "description": "Descubre cómo funciona el proceso de publicación continua de Tuist"
}
---
# Versiones

Tuist publica nuevas versiones automáticamente cuando los cambios se fusionan en la rama principal. La CLI, el servidor y el servidor de caché Kura se distribuyen a través de canales de lanzamiento (canary, release candidate, stable) para que la instalación recomendada sea estable y cambie con poca frecuencia; generar un release candidate y promoverlo a stable son pasos deliberados y semanales. La aplicación se lanza de forma continua (la app de iOS solo se despliega continuamente en TestFlight, consulta más [aquí](#app-store-release)).

## Descripción general

Lanzamos estos componentes principales:
- **Tuist CLI**: la herramienta de línea de comandos, distribuida a través de los [canales](#release-channels) canary, release candidate y stable
- **Tuist Server**: los servicios del backend, distribuidos mediante el mismo modelo de canales que la CLI
- **Kura**: el servidor de caché, distribuido mediante el mismo modelo de canales que la CLI
- **Tuist App**: las apps para macOS e iOS, lanzadas de forma continua (la app de iOS solo se despliega continuamente en TestFlight, consulta más [aquí](#app-store-release))

Cada push a `main` publica una prerelease canary para la CLI, el servidor y Kura. Una versión estable de cada uno de esos componentes se genera solo cuando un mantenedor promueve un release candidate probado, y el calendario semanal activa los tres trenes de lanzamiento al unísono (consulta [Canales de lanzamiento](#release-channels)). La app publica una versión estable en cada push a `main`.

## Cómo funciona

### 1. Convenciones de commits

Usamos [Conventional Commits](https://www.conventionalcommits.org/) para estructurar nuestros mensajes de commit. Esto permite que nuestras herramientas comprendan la naturaleza de los cambios, determinen los incrementos de versión y generen los changelogs adecuados.

Formato: `type(scope): description`

#### Tipos de commit y su impacto

| Tipo | Descripción | Impacto en la versión | Ejemplo |
|------|-------------|----------------|---------|
| `feat` | Nueva funcionalidad o capacidad | Incremento de versión menor (x.Y.z) | `feat(cli): add support for Swift 6` |
| `fix` | Corrección de errores | Incremento de versión patch (x.y.Z) | `fix(app): resolve crash when opening projects` |
| `docs` | Cambios en la documentación | Sin lanzamiento | `docs: update installation guide` |
| `style` | Cambios de estilo de código | Sin lanzamiento | `style: format code with swiftformat` |
| `refactor` | Refactorización de código | Sin lanzamiento | `refactor(server): simplify auth logic` |
| `perf` | Mejoras de rendimiento | Incremento de versión patch | `perf(cli): optimize dependency resolution` |
| `test` | Adiciones/cambios en tests | Sin lanzamiento | `test: add unit tests for cache` |
| `chore` | Tareas de mantenimiento | Sin lanzamiento | `chore: update dependencies` |
| `ci` | Cambios en CI/CD | Sin lanzamiento | `ci: add workflow for releases` |

Para la CLI, estos incrementos determinan la versión canary y la agrupación del changelog. Las versiones estables de la CLI son líneas menores (`X.Y.0`) generadas manualmente, y los parches estables (`X.Y.Z`) provienen únicamente de backports, por lo que un `feat` o `fix` llega a los usuarios de la CLI a través del flujo de canales descrito a continuación, en lugar de como un lanzamiento estable inmediato.

#### Cambios incompatibles

Los cambios incompatibles provocan un incremento de versión mayor (X.0.0) y deben indicarse en el cuerpo del commit:

```
feat(cli): change default cache location

BREAKING CHANGE: The cache is now stored in ~/.tuist/cache instead of .tuist-cache.
Users will need to clear their old cache directory.
```

### 2. Detección de cambios

Cada componente utiliza [git cliff](https://git-cliff.org/) para:
- Analizar los commits desde el último lanzamiento
- Filtrar los commits por ámbito (cli, app, server)
- Determinar si hay cambios publicables
- Generar changelogs automáticamente

### 3. Pipeline de lanzamiento

Cuando se detectan cambios publicables:

1. **Cálculo de versión**: El pipeline determina el siguiente número de versión
2. **Generación del changelog**: git cliff crea un changelog a partir de los mensajes de commit
3. **Proceso de compilación**: El componente se compila y prueba
4. **Generación de artefactos**: Se producen activos específicos del lanzamiento, como los paquetes de la CLI, las sumas de verificación y la especificación de la CLI `tuist.spec.json` generada a partir de `tuist --experimental-dump-help`
5. **Creación del lanzamiento**: Se crea un lanzamiento en GitHub con los artefactos
6. **Distribución**: Las actualizaciones se envían a los gestores de paquetes (por ejemplo, Homebrew para la CLI)

Para la app, esto produce un lanzamiento estable en cada merge. Para la CLI, el servidor y Kura, este mismo pipeline automático genera únicamente una prerelease **canary**; los release candidates y los lanzamientos estables se generan en el tren de lanzamiento semanal (consulta [Canales de lanzamiento](#release-channels)).

### 4. Filtrado por ámbito

Cada componente solo se lanza cuando tiene cambios relevantes:

- **CLI**: Commits con ámbito `(cli)` o sin ámbito
- **App**: Commits con ámbito `(app)`
- **Server**: Commits con ámbito `(server)`

## Canales de lanzamiento

La CLI, el servidor y Kura no se promocionan a un lanzamiento estable en cada push a `main`. Cada uno se distribuye a través de tres canales para que la instalación recomendada sea estable y cambie lentamente, mientras que los primeros adoptantes mantienen compilaciones por commit. La documentación orientada al usuario se encuentra en <.localized_link href="/cli/release-channels">Canales de lanzamiento de la CLI</.localized_link> y <.localized_link href="/guides/server/self-host/release-channels">Canales de lanzamiento del servidor</.localized_link>; esta sección es la guía operativa para mantenedores.

Cada componente utiliza los mismos tres canales:

| Canal | Versión | Generado por |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | Automáticamente, en cada push a `main` que afecte al componente (`<component>-release.yml`; para Kura, llamado por `server-production-deployment.yml` cuando cambia `kura/`) |
| Release candidate | `X.Y.0-rc.N` | Cada lunes, o manualmente, en una rama `releases/<component>-<major>.<minor>.x` (`<component>-rc.yml`) |
| Stable | `X.Y.Z` | Cada lunes, o manualmente, promoviendo un RC probado (`<component>-promote.yml`); parches mediante `<component>-backport.yml` |

Las compilaciones canary y RC se publican como prereleases de GitHub (nunca marcadas como "Latest", nunca mueven `:latest` en GHCR, nunca se envían a Homebrew para la CLI), por lo que los gestores de paquetes y los resolvedores de imágenes solo las seleccionan con una opt-in explícita. Canary siempre apunta a la siguiente versión menor no publicada: una vez que se genera una línea RC, la canary de `main` avanza a la siguiente versión menor.

Tuist alojado no espera al tren estable: el servidor se despliega por commit, y las versiones canary alojadas y de producción ejecutan la última canary de Kura. La cascada de despliegue publica esa canary antes de desplegarla, por lo que `kura-release.yml` no tiene su propio desencadenante. Los cambios exclusivos en las herramientas de lanzamiento de Kura (`mise/tasks/kura/**`, los flujos de trabajo `kura-*.yml`) no generan una canary.

Nunca eliges manualmente los números de versión. La siguiente versión de cada canal se deriva de las etiquetas git existentes mediante `mise/tasks/<component>/release/channel-version.sh`, al que invocan los flujos de trabajo siguientes.

Las ramas de lanzamiento tienen espacios de nombres por componente (`releases/server-X.Y.x`, `releases/kura-X.Y.x`, `releases/X.Y.x` para la CLI) para que las líneas de los tres componentes nunca colisionen en la misma versión menor.

### Calendario semanal

Cada lunes a las 06:00 UTC, los trabajos de promoción de los tres componentes se ejecutan al unísono: **Promoción de la CLI a Stable**, **Promoción del servidor a Stable** y **Promoción de Kura a Stable**. Cada uno promueve la línea RC más reciente que aún no es estable, que normalmente es la línea generada el lunes anterior. Si no existe tal línea, ese trabajo no publica nada.

Cuando finaliza una promoción, independientemente del resultado, su flujo de trabajo correspondiente de **Release Candidate** (`cli-rc.yml`, `server-rc.yml`, `kura-rc.yml`) se dispara mediante `workflow_run` y genera la siguiente línea desde `main`.

Si alguna ejecución programada falla o se cancela, se publica un mensaje en Slack. Una promoción falla cuando la rama de lanzamiento tiene commits posteriores a su último RC. Para lanzar esa línea, genera un nuevo RC en ella y promuévelo manualmente. De lo contrario, el siguiente lunes promoverá la línea más nueva.

### Generación de un release candidate

Para generar una nueva línea fuera del calendario semanal (sustituye el nombre del flujo de trabajo del componente a continuación):

1. Ejecuta el flujo de trabajo **\<Component\> Release Candidate** (por ejemplo, `server-rc.yml`) con una entrada `branch` vacía.
2. Publica `X.Y.0-rc.1` y, tras completarse con éxito, crea la rama protegida `releases/<component>-X.Y.x` en el commit compilado.

Para incorporar una corrección crítica o una regresión a una línea en prueba, haz cherry-pick sobre la rama de lanzamiento mediante un PR (el mismo flujo que los backports; la CI nunca hace cherry-pick) y luego itera el RC:

1. Crea una rama desde `releases/<component>-X.Y.x`, haz cherry-pick de la corrección, abre un PR hacia la rama de lanzamiento, resuelve cualquier conflicto y fusiona.
2. Vuelve a ejecutar el flujo de trabajo **Release Candidate** con `branch=releases/<component>-X.Y.x`. Publica `X.Y.0-rc.(N+1)` desde el HEAD de la rama.

Una línea en prueba está congelada en funcionalidades: solo se incorporan correcciones críticas y regresiones.

### Promoción a stable

Para promover una línea fuera del calendario semanal, después de que su RC haya pasado las pruebas limpiamente:

1. Ejecuta el flujo de trabajo **\<Component\> Promote to Stable** (por ejemplo, `server-promote.yml`) con `branch=releases/<component>-X.Y.x`.
2. Publica la imagen etiquetada con semver con `make_latest=true`, moviendo la etiqueta `:latest` de GHCR y el puntero "Latest" de GitHub. La CLI además actualiza la fórmula de Homebrew.

La promoción no se ejecuta a menos que el HEAD de la rama sea exactamente el commit al que apunta el último RC. Por lo tanto, si se ha fusionado alguna corrección en la línea después del último RC, debes generar un nuevo RC y dejarlo en prueba antes de que pueda lanzarse como stable.

### Backport de correcciones a una línea stable

Una vez que una línea es stable, lanza parches con el flujo de trabajo exclusivo de la CLI **Backport Release** (`cli-backport.yml`): haz cherry-pick de la corrección sobre `releases/X.Y.x` mediante un PR y luego ejecuta el flujo de trabajo con esa rama para generar `X.Y.(Z+1)`. Los backports nunca mueven el puntero "Latest" ni la fórmula de Homebrew. Se mantienen dos líneas simultáneamente: la línea actual recibe regresiones y correcciones de seguridad, mientras que la línea anterior solo recibe correcciones críticas y de seguridad. Otras correcciones de errores no se hacen backport y se lanzan con la siguiente versión menor.

Para el servidor y Kura, utiliza **Server Backport Release** (`server-backport.yml`) o **Kura Backport Release** (`kura-backport.yml`). La promoción publica únicamente el `X.Y.0` de un RC; no puede parchear una línea ya stable.

1. Partiendo de la última etiqueta stable publicada del componente en la línea `X.Y` seleccionada, abre un PR de corrección quirúrgica hacia su rama existente `releases/server-X.Y.x` o `releases/kura-X.Y.x`. Una versión menor o mayor más reciente no impide parchear una línea mantenida. Mantén fuera los cambios de main no relacionados.
2. Revisa y fusiona el PR de origen. Obtén la rama de lanzamiento remota y valida su **punta fusionada final**, incluidas las plataformas compatibles del componente y los controles positivos/negativos de TLS. Un HEAD pre-fusión exitoso no valida un commit squash o merge diferente.
3. Con aprobación de publicación separada, despacha el flujo de trabajo de backport correspondiente **desde main**, estableciendo `source_sha` en esa punta fusionada validada exacta y `base_tag` en la etiqueta stable actual, como `server@X.Y.Z` o `kura@X.Y.Z`. El flujo de trabajo deriva `X.Y.(Z+1)`; los operadores no eligen un incremento menor ni promueven contenidos canary.

La planificación actualiza la rama remota exacta y la etiqueta base, exige que el origen seleccionado coincida con la punta de la rama, rechaza un origen sin cambios o cambios fuera del componente, sus entradas de política de confianza y validación, y fija el commit base resuelto. Los controles originados en main repiten esas comprobaciones inmediatamente antes de la publicación de la imagen versionada y en GitHub. Si cambia la rama de origen, la base stable o la versión disponible, detente y vuelve a validar en lugar de sustituir por un nuevo origen.

Los backports utilizan los publicadores multiplataforma existentes sin mover el puntero "Latest" de GitHub ni `:latest` de GHCR. La publicación es independiente del despliegue alojado: estos flujos de trabajo no promueven un servidor alojado ni la flota de Kura, no omiten la aceptación canary ni validan un runtime instalado. Los ayudantes de compilación y los Dockerfiles siguen procediendo del origen stable seleccionado. Los controles son puertas de publicación, no trabajos de compilación sin credenciales; las compilaciones pueden subir resúmenes de imágenes sin etiquetar antes de la puerta final. La publicación de imágenes y en GitHub no es atómica: si la puerta posterior falla después de publicar una etiqueta de imagen, inspecciona la liberación parcial y conserva su origen y artefactos originales. Nunca sustituyas una liberación existente ni uses bytes diferentes bajo su etiqueta.

## Redacción de buenos mensajes de commit

Dado que los mensajes de commit influyen directamente en las notas de lanzamiento, es importante escribir mensajes claros y descriptivos:

### Haz:
- Usa el presente: "add feature" en lugar de "added feature"
- Sé conciso pero descriptivo
- Incluye el ámbito cuando los cambios sean específicos de un componente
- Referencia issues cuando corresponda: `fix(cli): resolve build cache issue (#1234)`

### No hagas:
- Usar mensajes vagos como "fix bug" o "update code"
- Mezclar múltiples cambios no relacionados en un solo commit
- Olvidar incluir información sobre cambios rupturistas

### Cambios rupturistas

Para cambios rupturistas, incluye `BREAKING CHANGE:` en el cuerpo del commit:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Flujos de trabajo de lanzamiento

La CLI, el servidor y Kura tienen cada uno su propio conjunto de flujos de trabajo de canal, siguiendo la misma estructura:

- `<component>-release.yml`: publica una canary en cada push a `main` que afecte al componente (el de Kura es un flujo reutilizable que `server-production-deployment.yml` llama cuando cambia `kura/`)
- `<component>-rc.yml`: genera un release candidate cada lunes (mediante `workflow_run` después de la promoción) o genera o itera uno manualmente
- `<component>-promote.yml`: promueve el RC pendiente a stable cada lunes a las 06:00 UTC o promueve manualmente un RC en prueba
- `<component>-build-publish.yml`: la tubería compartida de compilación y publicación que invocan los tres anteriores

La CLI, el servidor y Kura tienen además `<component>-backport.yml` para generar parches en una línea stable. Todos los flujos de trabajo de un componente se serializan a través de un único grupo de concurrencia `<component>-publish` para que la resolución de versiones y el etiquetado nunca entren en conflicto. Kura es la excepción: su canary usa `kura-canary-publish` y su RC, promoción y backport usan `kura-stable-publish`, así que una compilación stable larga nunca retrasa la cascada de despliegue. Los espacios de nombres de etiquetas son disjuntos, por lo que los dos grupos no pueden colisionar.

El chart de Helm y las imágenes de infraestructura (operador CAPI, controlador de runners, imagen del procesador xcresult, imagen del runner Linux, etc.) siguen publicándose a través de `.github/workflows/server-production-deployment.yml`. Se ejecuta en los pushes a `main` y aplica la cascada canary → pruebas de aceptación → producción para el despliegue alojado, y publica esos componentes de infraestructura a medida que cambian. La app, la caché, el plugin de Gradle, las skills, Noora y los controladores de infraestructura independientes tienen cada uno un flujo de trabajo dedicado `*-release.yml`. Todos comparten la detección de cambios: `mise/tasks/release/components.json` declara el prefijo de etiqueta y las rutas incluidas de cada componente, y git cliff convierte los commits coincidentes en notas de lanzamiento.

La compilación de la CLI (`cli-build-publish.yml`) también genera y publica un artefacto `tuist.spec.json` (generado a partir de `tuist --experimental-dump-help`) para que las herramientas downstream puedan consumir la interfaz de comandos.

## Seguimiento de lanzamientos

Puedes hacer seguimiento de los lanzamientos a través de:
- [Página de GitHub Releases](https://github.com/tuist/tuist/releases)
- Pestaña de GitHub Actions para las ejecuciones de flujos de trabajo
- Archivos de changelog en el directorio de cada componente

## Beneficios

Este enfoque de lanzamiento continuo proporciona:

- **Entrega rápida**: Los cambios llegan a los usuarios inmediatamente después de fusionarse
- **Menos cuellos de botella**: Sin esperas por lanzamientos manuales
- **Comunicación clara**: Changelogs automatizados a partir de mensajes de commit
- **Proceso consistente**: El mismo flujo de lanzamiento para todos los componentes
- **Garantía de calidad**: Solo se lanzan cambios probados

## Solución de problemas

Si un lanzamiento falla:

1. Revisa los registros de GitHub Actions del flujo de trabajo fallido
2. Asegúrate de que tus mensajes de commit sigan el formato convencional
3. Verifica que todas las pruebas pasen
4. Comprueba que el componente se compile correctamente

Para correcciones urgentes que necesiten un lanzamiento inmediato:
1. Asegúrate de que tu commit tenga un ámbito claro
2. Después de fusionar, supervisa el flujo de trabajo de lanzamiento
3. Para el servidor o la app, la corrección se publica en el siguiente push; si es necesario, activa un lanzamiento manual
4. Para la CLI, la corrección llega a canary automáticamente. Para llevarla a los usuarios de stable, haz backport a la(s) línea(s) stable mantenida(s) (consulta [Backporting fixes to a stable line](#backporting-fixes-to-a-stable-line))

## Lanzamiento en App Store

Mientras que la CLI y el Server siguen el proceso de lanzamiento continuo descrito anteriormente, la **app de iOS** es una excepción debido al proceso de revisión de la App Store de Apple:

- **Lanzamientos manuales**: Los lanzamientos de la app de iOS requieren envío manual a la App Store
- **Retrasos en la revisión**: Cada lanzamiento debe pasar por el proceso de revisión de Apple, que puede tardar entre 1 y 7 días
- **Cambios agrupados**: Múltiples cambios suelen empaquetarse juntos en cada lanzamiento de iOS
- **TestFlight**: Las versiones beta pueden distribuirse a través de TestFlight antes del lanzamiento en App Store
- **Notas de lanzamiento**: Deben escribirse específicamente según las directrices de App Store

La app de iOS sigue siguiendo las mismas convenciones de commit y usa git cliff para generar el changelog, pero el lanzamiento real a los usuarios ocurre con menor frecuencia y en un calendario manual.
