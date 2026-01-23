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
- Un proyecto
  <LocalizedLink href="/guides/features/projects">generado.</LocalizedLink>
- Una cuenta y un proyecto
  <LocalizedLink href="/guides/server/accounts-and-projects">Tuist.</LocalizedLink>
<!-- -->
:::

La caché del módulo Tuist proporciona una forma eficaz de optimizar los tiempos
de compilación al almacenar los módulos como binarios (`.xcframework`s) y
compartirlos entre diferentes entornos. Esta capacidad le permite aprovechar los
binarios generados anteriormente, lo que reduce la necesidad de compilaciones
repetidas y acelera el proceso de desarrollo.

## Advertencia {#warming}

Tuist utiliza de manera eficiente
<LocalizedLink href="/guides/features/projects/hashing">hash</LocalizedLink>
para cada objetivo en el gráfico de dependencia con el fin de detectar cambios.
Utilizando estos datos, crea y asigna identificadores únicos a los binarios
derivados de estos objetivos. En el momento de la generación del gráfico, Tuist
sustituye de forma fluida los objetivos originales por sus versiones binarias
correspondientes.

Esta operación, conocida como «calentamiento» de la caché ( *),* produce
binarios para uso local o para compartir con compañeros de equipo y entornos de
CI a través de Tuist. El proceso de calentamiento de la caché es sencillo y se
puede iniciar con un simple comando:


```bash
tuist cache
```

El comando reutiliza los binarios para acelerar el proceso.

## Uso {#usage}

De forma predeterminada, cuando los comandos de Tuist requieren la generación de
proyectos, sustituyen automáticamente las dependencias por sus equivalentes
binarios de la caché, si están disponibles. Además, si se especifica una lista
de objetivos en los que centrarse, Tuist también sustituirá cualquier objetivo
dependiente por sus binarios almacenados en caché, siempre que estén
disponibles. Para aquellos que prefieran un enfoque diferente, existe la opción
de desactivar completamente este comportamiento mediante el uso de un indicador
específico:

::: grupo de códigos
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

::: advertencia
<!-- -->
El almacenamiento en caché binario es una función diseñada para flujos de
trabajo de desarrollo, como ejecutar la aplicación en un simulador o
dispositivo, o realizar pruebas. No está pensada para compilaciones de
lanzamiento. Al archivar la aplicación, genere un proyecto con las fuentes
utilizando `--cache-profile none`.
<!-- -->
:::

## Perfiles de caché {#cache-profiles}

Tuist admite perfiles de caché para controlar la agresividad con la que se
sustituyen los objetivos por binarios almacenados en caché al generar proyectos.

- Elementos integrados:
  - `only-external`: reemplazar solo las dependencias externas (predeterminado
    del sistema)
  - `all-possible`: reemplazar tantos objetivos como sea posible (incluidos los
    objetivos internos).
  - `none`: nunca sustituir por binarios almacenados en caché.

Selecciona un perfil con `--cache-profile` en `tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

::: info DEPRECATED FLAG
<!-- -->
La bandera `--no-binary-cache` está obsoleta. Utilice `--cache-profile none` en
su lugar. La bandera obsoleta sigue funcionando por motivos de compatibilidad
con versiones anteriores.
<!-- -->
:::

Precedencia a la hora de resolver el comportamiento efectivo (de mayor a menor):

1. `--cache-profile none`
2. Enfoque objetivo (pasar objetivos a `generar`) → perfil `todas las
   posibilidades`
3. `--cache-profile `
4. Configuración predeterminada (si está establecida)
5. Predeterminado del sistema (`only-external`)

## Productos compatibles {#supported-products}

Tuist solo puede almacenar en caché los siguientes productos de destino:

- Frameworks (estáticos y dinámicos) que no dependen de
  [XCTest](https://developer.apple.com/documentation/xctest)
- Paquetes
- Macros de Swift

Estamos trabajando para dar soporte a bibliotecas y objetivos que dependen de
XCTest.

::: info UPSTREAM DEPENDENCIES
<!-- -->
Cuando un objetivo no se puede almacenar en caché, los objetivos ascendentes
tampoco se pueden almacenar en caché. Por ejemplo, si tienes el gráfico de
dependencias `A &gt; B`, donde A depende de B, si B no se puede almacenar en
caché, A tampoco se podrá almacenar en caché.
<!-- -->
:::

## Eficiencia {#efficiency}

El nivel de eficiencia que se puede alcanzar con el almacenamiento en caché
binario depende en gran medida de la estructura del gráfico. Para obtener los
mejores resultados, recomendamos lo siguiente:

1. Evita los gráficos de dependencia muy anidados. Cuanto menos complejo sea el
   gráfico, mejor.
2. Defina las dependencias con objetivos de protocolo/interfaz en lugar de con
   objetivos de implementación, e inyecte las implementaciones de dependencia
   desde los objetivos más altos.
3. Divida los objetivos que se modifican con frecuencia en otros más pequeños
   cuya probabilidad de cambio sea menor.

Las sugerencias anteriores forman parte de
<LocalizedLink href="/guides/features/projects/tma-architecture">La arquitectura
modular</LocalizedLink>, que proponemos como una forma de estructurar sus
proyectos para maximizar los beneficios no solo del almacenamiento en caché
binario, sino también de las capacidades de Xcode.

## Configuración recomendada {#recommended-setup}

Recomendamos tener un trabajo de CI que **se ejecute en cada confirmación en la
rama principal** para calentar la caché. Esto garantizará que la caché siempre
contenga binarios para los cambios en `main`, de modo que la rama local y la
rama de CI se construyan incrementalmente sobre ellos.

::: tip CACHE WARMING USES BINARIES
<!-- -->
El comando `tuist cache` también utiliza la caché binaria para acelerar el
calentamiento.
<!-- -->
:::

A continuación se muestran algunos ejemplos de flujos de trabajo habituales:

### Un desarrollador comienza a trabajar en una nueva función. {#a-developer-starts-to-work-on-a-new-feature}

1. Crean una nueva rama desde `main`.
2. They run `tuist generate`.
3. Tuist extrae los binarios más recientes de `main` y genera el proyecto con
   ellos.

### Un desarrollador envía los cambios al upstream. {#a-developer-pushes-changes-upstream}

1. El proceso de CI ejecutará `xcodebuild build` o `tuist test` para compilar o
   probar el proyecto.
2. El flujo de trabajo extraerá los binarios más recientes de `main` y generará
   el proyecto con ellos.
3. A continuación, compilará o probará el proyecto de forma incremental.

## Configuración {#configuration}

### Límite de concurrencia de la caché {#cache-concurrency-limit}

De forma predeterminada, Tuist descarga y carga artefactos de caché sin ningún
límite de concurrencia, lo que maximiza el rendimiento. Puede controlar este
comportamiento utilizando la variable de entorno
`TUIST_CACHE_CONCURRENCY_LIMIT`:

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

Esto puede resultar útil en entornos con un ancho de banda de red limitado o
para reducir la carga del sistema durante las operaciones de caché.

## Solución de problemas {#troubleshooting}

### No utiliza binarios para mis objetivos. {#it-doesnt-use-binaries-for-my-targets}

Asegúrate de que los hash
<LocalizedLink href="/guides/features/projects/hashing#debugging"> sean
deterministas</LocalizedLink> en todos los entornos y ejecuciones. Esto puede
ocurrir si el proyecto tiene referencias al entorno, por ejemplo, a través de
rutas absolutas. Puedes utilizar el comando `diff` para comparar los proyectos
generados por dos invocaciones consecutivas de `tuist generate` o entre entornos
o ejecuciones.

Asegúrate también de que el destino no dependa directa o indirectamente de un
<LocalizedLink href="/guides/features/cache/generated-project#supported-products">destino
no almacenable en caché</LocalizedLink>.

### Símbolos que faltan {#missing-symbols}

Al utilizar fuentes, el sistema de compilación de Xcode, a través de Derived
Data, puede resolver dependencias que no se declaran explícitamente. Sin
embargo, cuando se utiliza la caché binaria, las dependencias deben declararse
explícitamente; de lo contrario, es probable que se produzcan errores de
compilación cuando no se encuentren los símbolos. Para depurar esto,
recomendamos utilizar el comando
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist
inspect dependencies --only implicit`</LocalizedLink> y configurarlo en CI para
evitar regresiones en los enlaces implícitos.

### Caché del módulo heredado {#legacy-module-cache}

En Tuist `4.128.0`, hemos establecido nuestra nueva infraestructura para la
caché del módulo como predeterminada. Si experimenta problemas con esta nueva
versión, puede volver al comportamiento de la caché heredada configurando la
variable de entorno `TUIST_LEGACY_MODULE_CACHE`.

Esta caché del módulo heredado es una solución temporal y se eliminará del
servidor en una futura actualización. Planifica su migración.

```bash
export TUIST_LEGACY_MODULE_CACHE=1
tuist generate
```
