---
{
  "title": "Versiones",
  "titleTemplate": ":title | Colaboradores | Tuist",
  "description": "Descubre cómo funciona el proceso de lanzamientos continuos de Tuist"
}
---
# Versiones

Tuist publica nuevas versiones automáticamente cuando los cambios se fusionan en la rama principal. La CLI, el servidor y el servidor de caché Kura se distribuyen a través de canales de lanzamiento (canary, release candidate, stable) para que la instalación recomendada sea estable y cambie con poca frecuencia; crear un release candidate y promoverlo a estable son pasos deliberados que se realizan semanalmente. La aplicación se lanza continuamente (la app de iOS solo se despliega continuamente a TestFlight, consulta más [aquí](#app-store-release)).

## Descripción general

Lanzamos estos componentes principales:
- **Tuist CLI**: la herramienta de línea de comandos, distribuida a través de los [canales](#release-channels) canary, release candidate y stable
- **Tuist Server**: los servicios del backend, distribuidos mediante el mismo modelo de canales que la CLI
- **Kura**: el servidor de caché, distribuido mediante el mismo modelo de canales que la CLI
- **Tuist App**: las aplicaciones para macOS e iOS, lanzadas continuamente (la app de iOS solo se despliega continuamente a TestFlight, consulta más [aquí](#app-store-release))

Cada push a `main` publica una prerelease canary para la CLI, el servidor y Kura. Una versión estable de cada uno de esos componentes se crea únicamente cuando un mantenedor promueve un release candidate probado durante suficiente tiempo, y el calendario semanal dispara los tres trenes de forma sincronizada (consulta [Canales de lanzamiento](#release-channels)). La aplicación publica una versión estable en cada push a `main`.

## Cómo funciona

### 1. Convenciones de commits

Usamos [Conventional Commits](https://www.conventionalcommits.org/) para estructurar nuestros mensajes de commit. Esto permite que nuestras herramientas comprendan la naturaleza de los cambios, determinen los incrementos de versión y generen los changelogs correspondientes.

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
| `test` | Adiciones o cambios en tests | Sin lanzamiento | `test: add unit tests for cache` |
| `chore` | Tareas de mantenimiento | Sin lanzamiento | `chore: update dependencies` |
| `ci` | Cambios en CI/CD | Sin lanzamiento | `ci: add workflow for releases` |

Para la CLI, estos incrementos determinan la versión canary y la agrupación del changelog. Las versiones estables de la CLI son líneas menores (`X.Y.0`) creadas manualmente, y los parches estables (`X.Y.Z`) provienen únicamente de backports, por lo que un `feat` o `fix` llega a los usuarios de la CLI a través del flujo de canales descrito más abajo, en lugar de como un lanzamiento estable inmediato.

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
- Determinar si hay cambios que se puedan lanzar
- Generar changelogs automáticamente

### 3. Pipeline de lanzamiento

Cuando se detectan cambios lanzables:

1. **Cálculo de la versión**: el pipeline determina el siguiente número de versión
2. **Generación del changelog**: git cliff crea un changelog a partir de los mensajes de commit
3. **Proceso de compilación**: el componente se compila y se prueba
4. **Generación de artefactos**: se producen activos específicos del lanzamiento, como los paquetes de la CLI, las sumas de verificación y la especificación de la CLI `tuist.spec.json` generada a partir de `tuist --experimental-dump-help`
5. **Creación del lanzamiento**: se crea un lanzamiento en GitHub con los artefactos
6. **Distribución**: las actualizaciones se publican en los gestores de paquetes (por ejemplo, Homebrew para la CLI)

Para la aplicación, esto produce un lanzamiento estable en cada merge. Para la CLI, el servidor y Kura, este mismo pipeline automático produce únicamente una prerelease **canary**; los release candidates y los lanzamientos estables se crean en el tren de lanzamientos semanal (consulta [Canales de lanzamiento](#release-channels)).

### 4. Filtrado por ámbito

Cada componente solo se lanza cuando tiene cambios relevantes:

- **CLI**: commits con ámbito `(cli)` o sin ámbito
- **App**: commits con ámbito `(app)`
- **Server**: commits con ámbito `(server)`

## Canales de lanzamiento

La CLI, el servidor y Kura no se promueven a un lanzamiento estable en cada push a `main`. Cada uno se distribuye a través de tres canales para que la instalación recomendada sea estable y cambie lentamente, mientras que los early adopters mantienen builds por commit. La documentación orientada al usuario está disponible en <.localized_link href="/cli/release-channels">Canales de lanzamiento de la CLI</.localized_link> y <.localized_link href="/guides/server/self-host/release-channels">Canales de lanzamiento del servidor</.localized_link>; esta sección es el manual operativo para los mantenedores.

Cada componente utiliza los mismos tres canales:

| Canal | Versión | Creado por |
|---------|---------|--------|
| Canary | `X.Y.0-canary.N` | Automáticamente, en cada push a `main` que afecte al componente (`<component>-release.yml`; para Kura, lo invoca `server-production-deployment.yml` cuando cambia `kura/`) |
| Release candidate | `X.Y.0-rc.N` | Cada lunes, o manualmente, en una rama `releases/<component>-<major>.<minor>.x` (`<component>-rc.yml`) |
| Estable | `X.Y.Z` | Cada lunes, o manualmente, promoviendo un RC probado durante suficiente tiempo (`<component>-promote.yml`); parches mediante `<component>-backport.yml` |

Las builds canary y RC se publican como prereleases de GitHub (nunca marcadas como "Latest", nunca mueven `:latest` en GHCR, nunca se publican en Homebrew para la CLI), por lo que los gestores de paquetes y los resolvedores de imágenes solo las toman con opt-in explícito. Canary siempre apunta a la siguiente versión menor no publicada: una vez creada una línea RC, el canal canary de `main` avanza a la siguiente versión menor.

Tuist alojado no espera al tren estable: el servidor se despliega por commit, y los entornos hosted canary y producción ejecutan la última versión canary de Kura. La cascada de despliegue publica esa canary antes de desplegarla, por lo que `kura-release.yml` no tiene su propio trigger. Los cambios exclusivos en las herramientas de lanzamiento de Kura (`mise/tasks/kura/**`, los workflows `kura-*.yml`) no generan una canary.

Nunca eliges manualmente los números de versión. La siguiente versión de cada canal se deriva de las etiquetas de git existentes mediante `mise/tasks/<component>/release/channel-version.sh`, que invocan los workflows siguientes.

Las ramas de lanzamiento tienen espacios de nombres por componente (`releases/server-X.Y.x`, `releases/kura-X.Y.x`, `releases/X.Y.x` para la CLI) para que las líneas de los tres componentes nunca colisionen en la misma versión menor.

### Calendario semanal

Cada lunes a las 06:00 UTC, los trabajos de promoción de los tres componentes se ejecutan de forma sincronizada: **Promover CLI a estable**, **Promover Server a estable** y **Promover Kura a estable**. Cada uno promueve la línea RC más reciente que aún no es estable, que normalmente es la línea creada el lunes anterior. Si no existe tal línea, ese trabajo no publica nada.

Cuando finaliza una promoción, independientemente del resultado, su workflow correspondiente de **Release Candidate** (`cli-rc.yml`, `server-rc.yml`, `kura-rc.yml`) se dispara mediante `workflow_run` y crea la siguiente línea desde `main`.

Si alguna ejecución programada falla o se cancela, se publica un mensaje en Slack. Una promoción falla cuando la rama de lanzamiento tiene commits posteriores a su último RC. Para lanzar esa línea, crea un nuevo RC en ella y promuévelo manualmente. De lo contrario, el siguiente lunes promoverá la línea más nueva.

### Crear un release candidate

Para crear una nueva línea fuera del calendario semanal (sustituye el nombre del workflow del componente a continuación):

1. Ejecuta el workflow **Release Candidate de &lt;Componente&gt;** (por ejemplo, `server-rc.yml`) con un input `branch` vacío.
2. Publica `X.Y.0-rc.1` y, tras completarse con éxito, crea la rama protegida `releases/<component>-X.Y.x` en el commit compilado.

Para incorporar una corrección crítica o una regresión a una línea en periodo de prueba, haz cherry-pick hacia la rama de lanzamiento mediante un PR (el mismo flujo que los backports; CI nunca hace cherry-pick) y luego itera el RC:

1. Crea una rama desde `releases/<component>-X.Y.x`, haz cherry-pick de la corrección, abre un PR hacia la rama de lanzamiento, resuelve cualquier conflicto y haz merge.
2. Vuelve a ejecutar el workflow **Release Candidate** con `branch=releases/<component>-X.Y.x`. Publica `X.Y.0-rc.(N+1)` desde el HEAD de la rama.

Una línea en periodo de prueba está congelada en funcionalidades: solo se incorporan correcciones críticas y regresiones.

### Promover a estable

Para promover una línea fuera del calendario semanal, después de que su RC haya pasado limpiamente el periodo de prueba:

1. Ejecuta el workflow **Promover &lt;Componente&gt; a estable** (por ejemplo, `server-promote.yml`) con `branch=releases/<component>-X.Y.x`.
2. Publica la imagen etiquetada con semver con `make_latest=true`, moviendo la etiqueta `:latest` de GHCR y el puntero "Latest" de GitHub. La CLI además actualiza la fórmula de Homebrew.

La promoción no se ejecuta a menos que el HEAD de la rama sea exactamente el commit al que apunta el último RC. Por lo tanto, si alguna corrección se ha hecho merge en la línea después del último RC, debes crear un nuevo RC y dejarlo en periodo de prueba antes de que pueda lanzarse como estable.

### Hacer backport de correcciones a una línea estable

Una vez que una línea es estable, lanza parches con el workflow exclusivo de la CLI **Backport Release** (`cli-backport.yml`): haz cherry-pick de la corrección hacia `releases/X.Y.x` mediante un PR y luego ejecuta el workflow con esa rama para crear `X.Y.(Z+1)`. Los backports nunca mueven el puntero "Latest" ni la fórmula de Homebrew. Se mantienen dos líneas a la vez: la línea actual acepta regresiones y correcciones de seguridad; la línea anterior solo acepta correcciones críticas y de seguridad. Otras correcciones de bugs no se hacen backport y se lanzan con la siguiente versión menor.

Para el servidor y Kura, usa **Server Backport Release** (`server-backport.yml`) o **Kura Backport Release** (`kura-backport.yml`). La promoción solo publica el `X.Y.0` de un RC; no puede parchear una línea ya estable.

1. Comienza desde la última etiqueta estable publicada del componente en la línea `X.Y` seleccionada y abre un PR de corrección quirúrgica hacia su rama existente `releases/server-X.Y.x` o `releases/kura-X.Y.x`. Una versión menor o mayor más nueva no impide parchear una línea mantenida. Mantén fuera los cambios de main no relacionados.
2. Revisa y haz merge del PR de origen. Obtén la rama de lanzamiento remota y valida su **punta final tras el merge**, incluidas las plataformas compatibles del componente y los controles positivos/negativos de TLS. Un head pre-merge exitoso no valida un squash o commit de merge diferente.
3. Con aprobación de publicación por separado, despacha el workflow de backport correspondiente **desde main**, estableciendo `source_sha` en esa punta fusionada validada exacta y `base_tag` en la etiqueta estable actual, como `server@X.Y.Z` o `kura@X.Y.Z`. El workflow deriva `X.Y.(Z+1)`; los operadores no eligen un incremento menor ni promueven contenidos de canary.

El planning actualiza la rama remota exacta y la etiqueta base, exige que el origen seleccionado coincida con la punta de la rama, rechaza un origen sin cambios o cambios fuera del componente, sus inputs de política de confianza y su validación, y fija el commit base resuelto. Los controles originados en main repiten esas comprobaciones inmediatamente antes de la publicación de la imagen versionada y en GitHub. Si cambia la rama de origen, la base estable o la versión disponible, detente y vuelve a validar en lugar de sustituir por un nuevo origen.

Los backports usan los publicadores multiplataforma existentes sin mover el puntero "Latest" de GitHub ni `:latest` de GHCR. La publicación es independiente del despliegue alojado: estos workflows no promueven un servidor alojado ni la flota de Kura, no omiten la aceptación de canary ni validan un runtime instalado. Los helpers de build y los Dockerfiles siguen procediendo del origen estable seleccionado. Los controles son puertas de publicación, no trabajos de build sin credenciales; los builds pueden subir dígestos de imágenes sin etiqueta antes de la puerta final. La publicación de la imagen y en GitHub no es atómica: si la puerta posterior falla después de publicar una etiqueta de imagen, inspecciona la release parcial y conserva su origen y artefactos originales. Nunca reemplaces una release existente ni uses bytes diferentes bajo su etiqueta.

## Escribir buenos mensajes de commit

Dado que los mensajes de commit influyen directamente en las notas de lanzamiento, es importante escribir mensajes claros y descriptivos:

### Haz:
- Usa el presente: "add feature" en lugar de "added feature"
- Sé conciso pero descriptivo
- Incluye el alcance cuando los cambios sean específicos de un componente
- Referencia issues cuando corresponda: `fix(cli): resolve build cache issue (#1234)`

### No hagas:
- Usar mensajes vagos como "fix bug" o "update code"
- Mezclar múltiples cambios no relacionados en un solo commit
- Olvidar incluir información sobre cambios incompatibles

### Cambios incompatibles

Para cambios incompatibles, incluye `BREAKING CHANGE:` en el cuerpo del commit:

```
feat(cli): change cache directory structure

BREAKING CHANGE: Cache files are now stored in a new directory structure.
Users need to clear their cache after updating.
```

## Workflows de lanzamiento

La CLI, el servidor y Kura tienen cada uno su propio conjunto de workflows de canal, siguiendo la misma estructura:

- `<component>-release.yml` - publica una canary en cada push a `main` que afecte al componente (el de Kura es un workflow reutilizable que `server-production-deployment.yml` llama cuando cambia `kura/`)
- `<component>-rc.yml` - crea un release candidate cada lunes (mediante `workflow_run` tras la promoción) o crea o itera uno manualmente
- `<component>-promote.yml` - promueve el RC pendiente a estable cada lunes a las 06:00 UTC o promueve manualmente un RC que haya pasado el periodo de prueba
- `<component>-build-publish.yml` - la pipeline compartida de build y publicación que invocan los tres anteriores

La CLI, el servidor y Kura además tienen `<component>-backport.yml` para crear parches en una línea estable. Todos los workflows de un componente se serializan a través de un único grupo de concurrencia `<component>-publish` para que la resolución de versiones y el etiquetado nunca entren en competición. Kura es la excepción: su canary usa `kura-canary-publish` y su RC, promoción y backport usan `kura-stable-publish`, así un build estable largo nunca bloquea la cascada de despliegue. Los espacios de nombres de etiquetas son disjuntos, por lo que los dos grupos no pueden colisionar.

El chart de Helm y las imágenes de infraestructura (operador CAPI, controlador de runners, imagen del procesador de xcresult, imagen del runner de Linux, etc.) siguen publicándose a través de `.github/workflows/server-production-deployment.yml`. Se ejecuta en los pushes a `main` y aplica la cascada canary → pruebas de aceptación → producción para el despliegue alojado, y publica esos componentes de infraestructura a medida que cambian. La app, la caché, el plugin de Gradle, las skills, Noora y los controladores de infraestructura independientes tienen cada uno un workflow dedicado `*-release.yml`. Todos comparten la detección de cambios: `mise/tasks/release/components.json` declara el prefijo de etiqueta y las rutas incluidas de cada componente, y git cliff convierte los commits coincidentes en notas de lanzamiento.

El build de la CLI (`cli-build-publish.yml`) también produce y publica un artefacto `tuist.spec.json` (generado a partir de `tuist --experimental-dump-help`) para que las herramientas downstream puedan consumir la interfaz de comandos.

## Monitorización de lanzamientos

Puedes monitorizar los lanzamientos a través de:
- [Página de Releases de GitHub](https://github.com/tuist/tuist/releases)
- Pestaña de GitHub Actions para las ejecuciones de workflows
- Archivos de changelog en el directorio de cada componente

## Beneficios

Este enfoque de lanzamiento continuo ofrece:

- **Entrega rápida**: Los cambios llegan a los usuarios inmediatamente después de fusionarse
- **Menos cuellos de botella**: Sin esperas por lanzamientos manuales
- **Comunicación clara**: Changelogs automatizados a partir de los mensajes de commit
- **Proceso consistente**: Mismo flujo de lanzamiento para todos los componentes
- **Garantía de calidad**: Solo se lanzan cambios probados

## Solución de problemas

Si un lanzamiento falla:

1. Revisa los registros de GitHub Actions del workflow fallido
2. Asegúrate de que tus mensajes de commit sigan el formato convencional
3. Verifica que todos los tests pasen
4. Comprueba que el componente se compile correctamente

Para correcciones urgentes que necesiten un lanzamiento inmediato:
1. Asegúrate de que tu commit tenga un alcance claro
2. Después de fusionar, monitoriza el workflow de lanzamiento
3. Para el servidor o la app, la corrección se publica en el siguiente push; si es necesario, activa un lanzamiento manual
4. Para la CLI, la corrección llega automáticamente a canary. Para llevarla a los usuarios de la línea estable, haz backport a la(s) línea(s) estable(s) mantenida(s) (consulta [Hacer backport de correcciones a una línea estable](#backporting-fixes-to-a-stable-line))

## Lanzamiento en App Store

Mientras que la CLI y el Servidor siguen el proceso de lanzamiento continuo descrito anteriormente, la **app de iOS** es una excepción debido al proceso de revisión de la App Store de Apple:

- **Lanzamientos manuales**: Los lanzamientos de la app de iOS requieren envío manual a la App Store
- **Retrasos en la revisión**: Cada lanzamiento debe pasar por el proceso de revisión de Apple, que puede tardar entre 1 y 7 días
- **Cambios agrupados**: Varios cambios suelen agruparse en cada lanzamiento de iOS
- **TestFlight**: Las versiones beta pueden distribuirse mediante TestFlight antes del lanzamiento en la App Store
- **Notas de lanzamiento**: Deben escribirse específicamente según las directrices de la App Store

La app de iOS sigue siguiendo las mismas convenciones de commit y usa git cliff para generar el changelog, pero el lanzamiento real a los usuarios ocurre con menos frecuencia y de forma manual.
