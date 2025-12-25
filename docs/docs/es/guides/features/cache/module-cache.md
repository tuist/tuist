---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# Caché de módulos {#module-cache}

::: advertencia REQUISITOS
<!-- -->
- Un proyecto generado por
  <LocalizedLink href="/guides/features/projects"></LocalizedLink>
- A <LocalizedLink href="/guides/server/accounts-and-projects">Cuenta tuista y proyecto</LocalizedLink>
<!-- -->
:::

Tuist Module cache proporciona una potente forma de optimizar tus tiempos de
compilación almacenando en caché tus módulos como binarios (`.xcframework`s) y
compartiéndolos a través de diferentes entornos. Esta capacidad te permite
aprovechar los binarios generados previamente, reduciendo la necesidad de
repetir la compilación y acelerando el proceso de desarrollo.

## Calentamiento {#warming}

Tuist <LocalizedLink href="/guides/features/projects/hashing">utiliza eficientemente hashes</LocalizedLink> para cada objetivo en el grafo de
dependencia para detectar cambios. Utilizando estos datos, construye y asigna
identificadores únicos a los binarios derivados de estos objetivos. En el
momento de generar el grafo, Tuist sustituye sin problemas los objetivos
originales por sus correspondientes versiones binarias.

Esta operación, conocida como *"warming",* produce binarios para uso local o
para compartir con compañeros de equipo y entornos CI a través de Tuist. El
proceso de calentamiento de la caché es sencillo y puede iniciarse con un simple
comando:


```bash
tuist cache
```

El comando reutiliza binarios para acelerar el proceso.

## Uso {#usage}

Por defecto, cuando los comandos de Tuist necesitan generar un proyecto,
sustituyen automáticamente las dependencias por sus equivalentes binarios de la
caché, si están disponibles. Además, si especificas una lista de objetivos en
los que centrarte, Tuist también sustituirá cualquier objetivo dependiente por
sus binarios de la caché, siempre que estén disponibles. Para aquellos que
prefieren un enfoque diferente, hay una opción para optar por este
comportamiento por completo mediante el uso de una bandera específica:

::: grupo de códigos
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: advertencia
<!-- -->
La caché binaria es una función diseñada para flujos de trabajo de desarrollo,
como la ejecución de la aplicación en un simulador o dispositivo, o la ejecución
de pruebas. No está pensada para compilaciones de lanzamiento. Al archivar la
aplicación, genera un proyecto con los fuentes utilizando la opción
`--no-binary-cache`.
<!-- -->
:::

## Perfiles de caché {#cache-profiles}

Tuist admite perfiles de caché para controlar la agresividad con la que se
sustituyen los objetivos por binarios en caché al generar proyectos.

- Empotrados:
  - `only-external`: reemplaza sólo las dependencias externas (por defecto del
    sistema)
  - `all-possible`: reemplazar tantos objetivos como sea posible (incluidos los
    objetivos internos)
  - `none`: nunca reemplazar con binarios en caché

Seleccione un perfil con `--cache-profile` en `tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely (backwards compatible)
tuist generate --no-binary-cache  # equivalent to --cache-profile none
```

Precedencia a la hora de resolver la conducta efectiva (de mayor a menor):

1. `--no-binary-cache` → profile `none`
2. Enfoque de objetivos (pasar objetivos a `generar`) → perfil `todo-posible`
3. `--perfil de caché `
4. Configuración por defecto (si está configurada)
5. Sistema por defecto (`only-external`)

## Productos compatibles {#supported-products}

Tuist sólo puede almacenar en caché los siguientes productos de destino:

- Frameworks (estáticos y dinámicos) que no dependen de
  [XCTest](https://developer.apple.com/documentation/xctest)
- Paquetes
- Macros Swift

Estamos trabajando para dar soporte a las librerías y objetivos que dependen de
XCTest.

::: info UPSTREAM DEPENDENCIES
<!-- -->
Cuando un objetivo no es almacenable en caché, hace que los objetivos anteriores
tampoco lo sean. Por ejemplo, si tienes el gráfico de dependencias `A &gt; B`,
donde A depende de B, si B no es almacenable en caché, A tampoco lo será.
<!-- -->
:::

## Eficacia {#efficiency}

El nivel de eficacia que puede alcanzarse con la caché binaria depende en gran
medida de la estructura del grafo. Para obtener los mejores resultados,
recomendamos lo siguiente:

1. Evite los gráficos de dependencia muy anidados. Cuanto menos profundo sea el
   gráfico, mejor.
2. Define las dependencias con objetivos de protocolo/interfaz en lugar de
   objetivos de implementación, e inyecta las implementaciones de dependencias
   desde los objetivos superiores.
3. Dividir los objetivos modificados con frecuencia en otros más pequeños cuya
   probabilidad de cambio sea menor.

Las sugerencias anteriores forman parte de
<LocalizedLink href="/guides/features/projects/tma-architecture">La arquitectura modular</LocalizedLink>, que proponemos como una forma de estructurar sus
proyectos para maximizar los beneficios no sólo de la caché binaria, sino
también de las capacidades de Xcode.

## Configuración recomendada {#recommended-setup}

Recomendamos tener un trabajo CI que **ejecute en cada commit en la rama
principal** para calentar la caché. Esto asegurará que la caché siempre contenga
binarios para los cambios en `main` para que la rama local y CI construyan
incrementalmente sobre ellos.

::: tip CACHE WARMING USES BINARIES
<!-- -->
El comando `tuist cache` también hace uso de la caché binaria para acelerar el
calentamiento.
<!-- -->
:::

A continuación se ofrecen algunos ejemplos de flujos de trabajo habituales:

### Un desarrollador empieza a trabajar en una nueva función {#a-developer-starts-to-work-on-a-new-feature}

1. Crean una nueva rama a partir de `principal`.
2. Ejecutan `tuist generan`.
3. Tuist extrae los binarios más recientes de `main` y genera el proyecto con
   ellos.

### Un desarrollador introduce cambios {#a-developer-pushes-changes-upstream}

1. El proceso CI ejecutará `xcodebuild build` o `tuist test` para construir o
   probar el proyecto.
2. El flujo de trabajo extraerá los binarios más recientes de `main` y generará
   el proyecto con ellos.
3. A continuación, construirá o probará el proyecto de forma incremental.

## Configuración {#configuration}

### Límite de concurrencia de la caché {#cache-concurrency-limit}

Por defecto, Tuist descarga y sube artefactos de caché sin ningún límite de
concurrencia, maximizando el rendimiento. Puedes controlar este comportamiento
utilizando la variable de entorno `TUIST_CACHE_CONCURRENCY_LIMIT`:

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

Esto puede ser útil en entornos con un ancho de banda de red limitado o para
reducir la carga del sistema durante las operaciones de caché.

## Solución de problemas {#troubleshooting}

### No utiliza binarios para mis objetivos {#it-doesnt-use-binaries-for-my-targets}

Asegúrese de que los
<LocalizedLink href="/guides/features/projects/hashing#debugging">hashes son deterministas</LocalizedLink> entre entornos y ejecuciones. Esto puede ocurrir
si el proyecto tiene referencias al entorno, por ejemplo a través de rutas
absolutas. Puede utilizar el comando `diff` para comparar los proyectos
generados por dos invocaciones consecutivas de `tuist generate` o a través de
entornos o ejecuciones.

Asegúrese también de que el objetivo no depende directa o indirectamente de un
<LocalizedLink href="/guides/features/cache/generated-project#supported-products">objetivo no almacenable en caché</LocalizedLink>.

### Símbolos que faltan {#missing-symbols}

Cuando se utilizan fuentes, el sistema de compilación de Xcode, a través de los
datos derivados, puede resolver las dependencias que no se declaran
explícitamente. Sin embargo, cuando se confía en la caché binaria, las
dependencias deben declararse explícitamente; de lo contrario, es probable que
aparezcan errores de compilación cuando no se encuentren los símbolos. Para
depurar esto, recomendamos usar el comando
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect implicit-imports`</LocalizedLink> y configurarlo en CI para prevenir
regresiones en el enlazado implícito.
