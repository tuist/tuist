---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---
# Caché {#cache}

> [REQUISITOS
> - Un proyecto generado por
>   <LocalizedLink href="/guides/features/projects"></LocalizedLink>
> - A <LocalizedLink href="/guides/server/accounts-and-projects">Cuenta tuista y
>   proyecto</LocalizedLink>

El sistema de compilación de Xcode proporciona [compilaciones
incrementales](https://en.wikipedia.org/wiki/Incremental_build_model), mejorando
la eficiencia en circunstancias normales. Sin embargo, esta característica se
queda corta en [entornos de integración continua
(IC)](https://en.wikipedia.org/wiki/Continuous_integration), donde los datos
esenciales para las compilaciones incrementales no se comparten entre diferentes
compilaciones. Además, los desarrolladores de **suelen restablecer estos datos
localmente para solucionar problemas de compilación complejos**, lo que provoca
que las compilaciones limpias sean más frecuentes. Esto hace que los equipos
pasen demasiado tiempo esperando a que finalicen las compilaciones locales o a
que las canalizaciones de integración continua proporcionen información sobre
las solicitudes de extracción. Además, el frecuente cambio de contexto en un
entorno de este tipo agrava esta improductividad.

Tuist aborda estos retos con eficacia gracias a su función de almacenamiento en
caché. Esta herramienta optimiza el proceso de compilación almacenando en caché
los binarios compilados, lo que reduce significativamente los tiempos de
compilación tanto en entornos de desarrollo local como de CI. Este enfoque no
sólo acelera los bucles de retroalimentación, sino que también minimiza la
necesidad de cambiar de contexto, lo que en última instancia aumenta la
productividad.

## Calentamiento {#warming}

Tuist <LocalizedLink href="/guides/features/projects/hashing">utiliza
eficientemente hashes</LocalizedLink> para cada objetivo en el grafo de
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
:::

> [ADVERTENCIA] La caché binaria es una función diseñada para flujos de trabajo
> de desarrollo, como la ejecución de la aplicación en un simulador o
> dispositivo, o la ejecución de pruebas. No está pensada para compilaciones de
> lanzamiento. Al archivar la aplicación, genere un proyecto con los fuentes
> utilizando la opción `--no-binary-cache`.

## Productos compatibles {#supported-products}

Tuist sólo puede almacenar en caché los siguientes productos de destino:

- Frameworks (estáticos y dinámicos) que no dependen de
  [XCTest](https://developer.apple.com/documentation/xctest)
- Paquetes
- Macros Swift

Estamos trabajando para dar soporte a las librerías y objetivos que dependen de
XCTest.

> [Cuando un objetivo no es almacenable en caché, hace que los objetivos
> anteriores tampoco lo sean. Por ejemplo, si tienes el gráfico de dependencias
> `A &gt; B`, donde A depende de B, si B no es almacenable en caché, A tampoco
> lo será.

## Eficiencia {#efficiency}

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
<LocalizedLink href="/guides/features/projects/tma-architecture">La arquitectura
modular</LocalizedLink>, que proponemos como una forma de estructurar sus
proyectos para maximizar los beneficios no sólo de la caché binaria, sino
también de las capacidades de Xcode.

## Configuración recomendada {#recommended-setup}

Recomendamos tener un trabajo CI que **ejecute en cada commit en la rama
principal** para calentar la caché. Esto asegurará que la caché siempre contenga
binarios para los cambios en `main` para que la rama local y CI construyan
incrementalmente sobre ellos.

> [EL CALENTAMIENTO DE LA CACHE UTILIZA BINARIOS El comando `tuist cache`
> también hace uso de la caché binaria para acelerar el calentamiento.

A continuación se ofrecen algunos ejemplos de flujos de trabajo habituales:

### Un desarrollador empieza a trabajar en una nueva característica {#a-developer-starts-to-work-on-a-new-feature}

1. Crean una nueva rama a partir de `principal`.
2. Ejecutan `tuist generan`.
3. Tuist extrae los binarios más recientes de `main` y genera el proyecto con
   ellos.

### Un desarrollador empuja los cambios aguas arriba {#a-developer-pushes-changes-upstream}

1. El proceso CI ejecutará `tuist build` o `tuist test` para construir o probar
   el proyecto.
2. El flujo de trabajo extraerá los binarios más recientes de `main` y generará
   el proyecto con ellos.
3. A continuación, construirá o probará el proyecto de forma incremental.

## Solución de problemas {#troubleshooting}

### No utiliza binarios para mis objetivos {#it-doesnt-use-binaries-for-my-targets}

Asegúrese de que los
<LocalizedLink href="/guides/features/projects/hashing#debugging">hashes son
deterministas</LocalizedLink> entre entornos y ejecuciones. Esto puede ocurrir
si el proyecto tiene referencias al entorno, por ejemplo a través de rutas
absolutas. Puede utilizar el comando `diff` para comparar los proyectos
generados por dos invocaciones consecutivas de `tuist generate` o a través de
entornos o ejecuciones.

Asegúrese también de que el objetivo no depende directa o indirectamente de un
<LocalizedLink href="/guides/features/cache#supported-products">objetivo no
almacenable en caché</LocalizedLink>.
