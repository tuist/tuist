---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# La arquitectura modular (TMA) {#the-modular-architecture-tma}

TMA es un enfoque arquitectónico para estructurar aplicaciones de Apple OS con
el fin de permitir la escalabilidad, optimizar los ciclos de creación y prueba,
y garantizar las buenas prácticas en su equipo. Su idea central es crear
aplicaciones con funciones independientes interconectadas mediante API claras y
concisas.

Estas directrices introducen los principios de la arquitectura, ayudándole a
identificar y organizar las características de su aplicación en diferentes
capas. También presenta sugerencias, herramientas y consejos si decide utilizar
esta arquitectura.

::: info µCARACTERÍSTICAS
<!-- -->
Esta arquitectura se conocía anteriormente como µFeatures. La hemos rebautizado
como The Modular Architecture (TMA) para reflejar mejor su propósito y los
principios que la sustentan.
<!-- -->
:::

## Principio básico {#core-principle}

Los desarrolladores deben ser capaces de **construir, probar y probar** sus
características de forma rápida, independientemente de la aplicación principal,
y garantizando al mismo tiempo las características de Xcode como vistas previas
de interfaz de usuario, finalización de código, y el trabajo de depuración de
forma fiable.

## Qué es un módulo {#what-is-a-module}

Un módulo representa una característica de la aplicación y es una combinación de
los cinco objetivos siguientes (donde objetivo se refiere a un objetivo de
Xcode):

- **Fuente:** Contiene el código fuente de la función (Swift, Objective-C, C++,
  JavaScript...) y sus recursos (imágenes, fuentes, storyboards, xibs).
- **Interfaz:** Es un objetivo complementario que contiene la interfaz pública y
  los modelos de la función.
- **Pruebas:** Contiene las pruebas unitarias y de integración de la función.
- **Pruebas:** Proporciona datos de prueba que se pueden utilizar en las pruebas
  y en la aplicación de ejemplo. También proporciona mocks para clases de
  módulos y protocolos que pueden ser utilizados por otras funcionalidades como
  veremos más adelante.
- **Ejemplo:** Contiene una app de ejemplo que los desarrolladores pueden
  utilizar para probar la función en determinadas condiciones (diferentes
  idiomas, tamaños de pantalla, ajustes).

Recomendamos seguir una convención de nombres para los objetivos, algo que
puedes imponer en tu proyecto gracias al DSL de Tuist.

| Objetivo                | Dependencias                | Contenido                          |
| ----------------------- | --------------------------- | ---------------------------------- |
| `Característica`        | `FeatureInterface`          | Código fuente y recursos           |
| `FeatureInterface`      | -                           | Interfaz pública y modelos         |
| `FeatureTests`          | `Feature`, `FeatureTesting` | Pruebas unitarias y de integración |
| `FeatureTesting`        | `FeatureInterface`          | Prueba de datos y mocks            |
| `CaracterísticaEjemplo` | `FeatureTesting`, `Feature` | Ejemplo de aplicación              |

::: tip UI Previews
<!-- -->
`Feature` puede utilizar `FeatureTesting` como activo de desarrollo para
permitir previsualizaciones de la interfaz de usuario.
<!-- -->
:::

::: advertencia DIRECTIVAS DE COMPILACIÓN EN LUGAR DE OBJETIVOS DE PRUEBA
<!-- -->
Como alternativa, puedes utilizar directivas del compilador para incluir datos
de prueba y mocks en los objetivos `Feature` o `FeatureInterface` al compilar
para `Debug`. Simplificas el gráfico, pero acabarás compilando código que no
necesitarás para ejecutar la aplicación.
<!-- -->
:::

## Por qué un módulo {#why-a-module}

### API claras y concisas {#clear-and-concise-apis}

Cuando todo el código fuente de la aplicación vive en el mismo destino es muy
fácil crear dependencias implícitas en el código y acabar con el tan conocido
código espagueti. Todo está fuertemente acoplado, el estado es a veces
impredecible y la introducción de nuevos cambios se convierte en una pesadilla.
Cuando definimos funcionalidades en objetivos independientes necesitamos diseñar
APIs públicas como parte de la implementación de nuestra funcionalidad. Tenemos
que decidir qué debe ser público, cómo debe consumirse nuestra funcionalidad y
qué debe seguir siendo privado. Tenemos más control sobre cómo queremos que
nuestros clientes utilicen la funcionalidad y podemos imponer buenas prácticas
diseñando API seguras.

### Módulos pequeños {#small-modules}

[Divide y vencerás](https://en.wikipedia.org/wiki/Divide_and_conquer). Trabajar
en módulos pequeños permite centrarse más y probar la funcionalidad de forma
aislada. Además, los ciclos de desarrollo son mucho más rápidos ya que tenemos
una compilación más selectiva, compilando sólo los componentes que son
necesarios para que nuestra característica funcione. La compilación de toda la
aplicación sólo es necesaria al final de nuestro trabajo, cuando necesitamos
integrar la función en la aplicación.

### Reutilización {#reusability}

Se fomenta la reutilización de código entre aplicaciones y otros productos, como
las extensiones, mediante el uso de frameworks o bibliotecas. Construir módulos
y reutilizarlos es bastante sencillo. Podemos construir una extensión de
iMessage, una extensión de Today o una aplicación de watchOS simplemente
combinando módulos existentes y añadiendo _(cuando sea necesario)_ capas de
interfaz de usuario específicas de la plataforma.

## Dependencias {#dependencies}

Cuando un módulo depende de otro, declara una dependencia con respecto a su
interfaz de destino. Esto tiene una doble ventaja. Evita que la implementación
de un módulo se acople a la implementación de otro módulo, y acelera las
compilaciones limpias porque sólo tienen que compilar la implementación de
nuestra función y las interfaces de las dependencias directas y transitivas.
Este enfoque está inspirado en la idea de SwiftRock de [Reducir los tiempos de
compilación de iOS mediante el uso de módulos de
interfaz](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

Depender de interfaces requiere que las aplicaciones construyan el grafo de
implementaciones en tiempo de ejecución, y lo inyecten en dependencia en los
módulos que lo necesiten. Aunque TMA no opina sobre cómo hacerlo, recomendamos
utilizar soluciones de inyección de dependencias o patrones o soluciones que no
añadan indirecciones en tiempo de ejecución o utilicen API de plataforma que no
se diseñaron para este fin.

## Tipos de productos {#product-types}

Cuando construyes un módulo, puedes elegir entre **bibliotecas y frameworks**, y
**enlazado estático y dinámico** para los objetivos. Sin Tuist, tomar esta
decisión es un poco más complejo porque necesitas configurar el gráfico de
dependencias manualmente. Sin embargo, gracias a Tuist Projects, esto ya no es
un problema.

Recomendamos el uso de bibliotecas o marcos dinámicos durante el desarrollo
utilizando
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">accesores de paquetes</LocalizedLink> para desacoplar la lógica de acceso a paquetes de la
naturaleza de la biblioteca o marco del objetivo. Esto es clave para tiempos de
compilación rápidos y para asegurar que [SwiftUI
Previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode)
funcione de forma fiable. Y librerías estáticas o frameworks para las versiones
de lanzamiento para asegurar que la aplicación arranca rápido. Puede aprovechar
<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">la configuración dinámica</LocalizedLink> para cambiar el tipo de producto en el
momento de la generación:

```bash
# You'll have to read the value of the variable from the manifest {#youll-have-to-read-the-value-of-the-variable-from-the-manifest}
# and use it to change the linking type {#and-use-it-to-change-the-linking-type}
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```


::: advertencia BIBLIOTECAS FUSIBLES
<!-- -->
Apple intentó aliviar la incomodidad de cambiar entre bibliotecas estáticas y
dinámicas introduciendo [bibliotecas
fusionables](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries).
Sin embargo, esto introduce no-determinismo en el tiempo de compilación que hace
que tu compilación no sea reproducible y más difícil de optimizar, por lo que no
recomendamos su uso.
<!-- -->
:::

## Código {#code}

TMA no opina sobre la arquitectura del código y los patrones para sus módulos.
Sin embargo, nos gustaría compartir algunos consejos basados en nuestra
experiencia:

- **Aprovechar el compilador es genial.** Aprovechar demasiado el compilador
  puede acabar siendo improductivo y hacer que algunas funciones de Xcode, como
  las vistas previas, no funcionen de forma fiable. Recomendamos utilizar el
  compilador para aplicar buenas prácticas y detectar errores con antelación,
  pero no hasta el punto de hacer que el código sea más difícil de leer y
  mantener.
- **Utiliza las macros Swift con moderación.** Pueden ser muy potentes, pero
  también pueden hacer que el código sea más difícil de leer y mantener.
- **Adopta la plataforma y el lenguaje, no los abstraigas.** Intentar crear
  capas de abstracción elaboradas puede acabar siendo contraproducente. La
  plataforma y el lenguaje son lo suficientemente potentes como para crear
  grandes aplicaciones sin necesidad de capas de abstracción adicionales.
  Utiliza buenos patrones de programación y diseño como referencia para
  construir tus funcionalidades.

## Recursos {#resources}

- [Construyendo
  µCaracterísticas](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Framework Oriented
  Programming](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [Un viaje a los marcos y
  Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Aprovechar los frameworks para acelerar nuestro desarrollo en iOS - Parte
  1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Programación orientada a
  bibliotecas](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Construcción de marcos
  modernos](https://developer.apple.com/videos/play/wwdc2014/416/)
- [Guía no oficial de los archivos
  xcconfig](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Bibliotecas estáticas y
  dinámicas](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
