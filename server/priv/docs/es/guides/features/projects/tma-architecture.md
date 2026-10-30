---
{
  "title": "La arquitectura modular (TMA)",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Conoce la arquitectura modular (TMA) y cómo estructurar tus proyectos con ella."
}
---
# La arquitectura modular (TMA) {#the-modular-architecture-tma}

TMA es un enfoque arquitectónico para estructurar aplicaciones que permite la escalabilidad, optimiza los ciclos de compilación y tests, y garantiza buenas prácticas en tu equipo. Su idea central es construir tus apps mediante funcionalidades independientes interconectadas a través de APIs claras y concisas.

Estas directrices presentan los principios de la arquitectura y te ayudan a identificar y organizar las funcionalidades de tu aplicación en diferentes capas. También ofrecen consejos, herramientas y recomendaciones si decides usar esta arquitectura.

> [!NOTE]
> **Μfeatures**
>
> Esta arquitectura se conocía anteriormente como µFeatures. La hemos renombrado a La arquitectura modular (TMA) para reflejar mejor su propósito y los principios que la sustentan.


## Principio fundamental {#core-principle}

Los desarrolladores deben poder **compilar, probar y experimentar** con sus funcionalidades rápidamente, de forma independiente de la app principal, y asegurando que características de Xcode como las previsualizaciones de UI, la finalización de código y la depuración funcionen de manera fiable.

## ¿Qué es un módulo? {#what-is-a-module}

Un módulo representa una funcionalidad de la aplicación y está compuesto por los siguientes cinco targets (donde target se refiere a un target de Xcode):

- **Source:** Contiene el código fuente de la funcionalidad (Swift, Objective-C, C++, JavaScript...) y sus recursos (imágenes, fuentes, storyboards, xibs).
- **Interface:** Es un target complementario que contiene la interfaz pública y los modelos de la funcionalidad.
- **Tests:** Contiene los tests unitarios y de integración de la funcionalidad.
- **Testing:** Proporciona datos de prueba que pueden usarse en los tests y en la app de ejemplo. También ofrece mocks para las clases y protocolos del módulo que otras funcionalidades podrán utilizar, como veremos más adelante.
- **Example:** Contiene una app de ejemplo que los desarrolladores pueden usar para probar la funcionalidad bajo ciertas condiciones (diferentes idiomas, tamaños de pantalla, configuraciones).

Recomendamos seguir una convención de nomenclatura para los targets, algo que puedes aplicar en tu proyecto gracias al DSL de Tuist.

| Target | Dependencias | Contenido |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | Código fuente y recursos |
| `FeatureInterface` | - | Interfaz pública y modelos |
| `FeatureTests` | `Feature`, `FeatureTesting` | Tests unitarios y de integración |
| `FeatureTesting` | `FeatureInterface` | Datos de prueba y mocks |
| `FeatureExample` | `FeatureTesting`, `Feature` | App de ejemplo |

> [!TIP]
> **Previsualizaciones de UI**
>
> `Feature` puede usar `FeatureTesting` como recurso de desarrollo para habilitar las previsualizaciones de UI


> [!WARNING]
> **Directivas del compilador en lugar de targets de testing**
>
> Como alternativa, puedes usar directivas del compilador para incluir datos de prueba y mocks en los targets `Feature` o `FeatureInterface` al compilar para `Debug`. Simplificas el grafo, pero terminarás compilando código que no necesitarás para ejecutar la app.


## ¿Por qué un módulo? {#why-a-module}

### APIs claras y concisas {#clear-and-concise-apis}

Cuando todo el código fuente de la app reside en el mismo target, es muy fácil crear dependencias implícitas en el código y terminar con el tan conocido código espagueti. Todo está fuertemente acoplado, el estado es a veces impredecible y introducir nuevos cambios se convierte en una pesadilla. Cuando definimos funcionalidades en targets independientes, debemos diseñar APIs públicas como parte de la implementación de nuestra funcionalidad. Necesitamos decidir qué debe ser público, cómo se consumirá nuestra funcionalidad y qué debe permanecer privado. Tenemos más control sobre cómo queremos que los clientes de nuestra funcionalidad la utilicen y podemos imponer buenas prácticas diseñando APIs seguras.

### Módulos pequeños {#small-modules}

[Divide y vencerás](https://en.wikipedia.org/wiki/Divide_and_conquer). Trabajar con módulos pequeños te permite concentrarte más y probar y experimentar con la funcionalidad de forma aislada. Además, los ciclos de desarrollo son mucho más rápidos porque tenemos una compilación más selectiva, compilando solo los componentes necesarios para que nuestra funcionalidad funcione. La compilación de toda la app solo es necesaria al final de nuestro trabajo, cuando necesitamos integrar la funcionalidad en la app.

### Reutilización {#reusability}

Se fomenta la reutilización de código entre apps y otros productos como extensiones mediante frameworks o librerías. Al construir módulos, reutilizarlos es bastante sencillo. Podemos construir una extensión de iMessage, una Today Extension o una aplicación para watchOS simplemente combinando módulos existentes y añadiendo _(cuando sea necesario)_ capas de UI específicas de la plataforma.

## Dependencias {#dependencies}

Cuando un módulo depende de otro, declara una dependencia contra su target de interfaz. Esto tiene dos ventajas. Evita que la implementación de un módulo esté acoplada a la implementación de otro y acelera las compilaciones limpias, ya que solo tienen que compilar la implementación de nuestra funcionalidad y las interfaces de las dependencias directas y transitivas. Este enfoque está inspirado en la idea de SwiftRock de [Reducir los tiempos de compilación en iOS usando módulos de interfaz](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets).

Depender de interfaces requiere que las apps construyan el grafo de implementaciones en tiempo de ejecución e inyecten las dependencias en los módulos que las necesiten. Aunque TMA no impone una forma concreta de hacerlo, recomendamos usar soluciones o patrones de inyección de dependencias que no añadan indirecciones en tiempo de compilación ni utilicen APIs de la plataforma que no fueron diseñadas para este fin.

## Tipos de producto {#product-types}

Al construir un módulo, puedes elegir entre **librerías y frameworks**, y entre **enlazado estático y dinámico** para los targets. Sin Tuist, tomar esta decisión es un poco más complejo porque necesitas configurar el grafo de dependencias manualmente. Sin embargo, gracias a Tuist Projects, esto ya no es un problema.

Recomendamos usar librerías o frameworks dinámicos durante el desarrollo mediante <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">accesores de bundle</.localized_link> para desacoplar la lógica de acceso al bundle de la naturaleza de librería o framework del target. Esto es clave para lograr tiempos de compilación rápidos y garantizar que las [Previsualizaciones de SwiftUI](https://developer.apple.com/documentation/swiftui/previews-in-xcode) funcionen de manera fiable. Y usa librerías o frameworks estáticos para las compilaciones de release para asegurar que la app arranque rápido. Puedes aprovechar la <.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">configuración dinámica</.localized_link> para cambiar el tipo de producto en tiempo de generación:

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


> [!WARNING]
> **Librerías combinables**
>
> Apple intentó aliviar la complejidad de cambiar entre librerías estáticas y dinámicas introduciendo las [librerías combinables](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries). Sin embargo, esto introduce no determinismo en tiempo de compilación que hace que tu compilación no sea reproducible y más difícil de optimizar, por lo que no recomendamos su uso.


## Código {#code}

TMA no impone opiniones sobre la arquitectura de código y los patrones para tus módulos. Sin embargo, nos gustaría compartir algunos consejos basados en nuestra experiencia:

- **Aprovechar el compilador es genial.** Exagerar su uso puede resultar improductivo y hacer que algunas funcionalidades de Xcode, como las previsualizaciones, funcionen de manera poco fiable. Recomendamos usar el compilador para imponer buenas prácticas y detectar errores pronto, pero sin llegar al punto de que el código sea más difícil de leer y mantener.
- **Usa las macros de Swift con moderación.** Pueden ser muy potentes, pero también pueden hacer que el código sea más difícil de leer y mantener.
- **Acepta la plataforma y el lenguaje, no los abstraigas.** Intentar crear capas de abstracción elaboradas puede resultar contraproducente. La plataforma y el lenguaje son lo suficientemente potentes para construir grandes apps sin necesidad de capas de abstracción adicionales. Usa buenos patrones de programación y diseño como referencia para construir tus funcionalidades.


## Recursos {#resources}

- [Construyendo µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [Programación orientada a frameworks](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [Un viaje hacia los frameworks y Swift](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [Aprovechando los frameworks para acelerar nuestro desarrollo en iOS - Parte 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [Programación orientada a librerías](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [Construyendo frameworks modernos](https://developer.apple.com/videos/play/wwdc2014/416/)
- [La guía no oficial de archivos xcconfig](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [Librerías estáticas y dinámicas](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
