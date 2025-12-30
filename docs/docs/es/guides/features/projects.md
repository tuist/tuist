---
{
  "title": "Projects",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn about Tuist's DSL for defining Xcode projects."
}
---
# Proyectos generados {#generated-projects}

Generated es una alternativa viable que ayuda a superar estos retos manteniendo
la complejidad y los costes a un nivel aceptable. Considera los proyectos de
Xcode como un elemento fundamental, garantizando la resistencia frente a futuras
actualizaciones de Xcode, y aprovecha la generación de proyectos de Xcode para
proporcionar a los equipos una API declarativa centrada en la modularización.
Tuist utiliza la declaración de proyectos para simplificar las complejidades de
la modularización**, optimizar flujos de trabajo como la compilación o las
pruebas en varios entornos, y facilitar y democratizar la evolución de los
proyectos Xcode.

## ¿Cómo funciona? {#cómo-funciona}

Para empezar a trabajar con proyectos generados, todo lo que necesitas es
definir tu proyecto utilizando **Tuist's Domain Specific Language (DSL)**. Esto
implica el uso de archivos de manifiesto como `Workspace.swift` o
`Project.swift`. Si ya has trabajado con el gestor de paquetes Swift, el enfoque
es muy similar.

Una vez definido el proyecto, Tuist ofrece varios flujos de trabajo para
gestionarlo e interactuar con él:

- **Generar:** Este es un flujo de trabajo fundamental. Utilízalo para crear un
  proyecto Xcode compatible con Xcode.
- **<LocalizedLink href="/guides/features/build">Build</LocalizedLink>:** Este
  flujo de trabajo no sólo genera el proyecto Xcode, sino que también emplea
  `xcodebuild` para compilarlo.
- **<LocalizedLink href="/guides/features/test">Prueba</LocalizedLink>:** Al
  igual que el flujo de trabajo de compilación, no sólo genera el proyecto de
  Xcode, sino que utiliza `xcodebuild` para probarlo.

## Desafíos con proyectos Xcode {#challenges-with-xcode-projects}

A medida que crecen los proyectos de Xcode, las organizaciones **pueden
enfrentarse a un descenso de la productividad** debido a varios factores, como
las compilaciones incrementales poco fiables, la limpieza frecuente de la caché
global de Xcode por parte de los desarrolladores que se encuentran con problemas
y las configuraciones frágiles de los proyectos. Para mantener el rápido
desarrollo de características, las organizaciones suelen explorar varias
estrategias.

Algunas organizaciones optan por eludir el compilador abstrayendo la plataforma
mediante tiempos de ejecución dinámicos basados en JavaScript, como [React
Native](https://reactnative.dev/). Aunque este enfoque puede ser eficaz,
[complica el acceso a las funciones nativas de la
plataforma](https://shopify.engineering/building-app-clip-react-native). Otras
organizaciones optan por **modularizando el código base**, lo que ayuda a
establecer límites claros, facilitando el trabajo con el código base y mejorando
la fiabilidad de los tiempos de compilación. Sin embargo, el formato de proyecto
de Xcode no está diseñado para la modularidad y da lugar a configuraciones
implícitas que pocos entienden y a frecuentes conflictos. Esto conduce a un mal
factor de bus, y aunque las construcciones incrementales pueden mejorar, los
desarrolladores todavía pueden borrar con frecuencia la caché de construcción de
Xcode (es decir, los datos derivados) cuando las construcciones fallan. Para
solucionar esto, algunas organizaciones eligen **abandonar el sistema de
compilación de Xcode** y adoptar alternativas como [Buck](https://buck.build/) o
[Bazel](https://bazel.build/). Sin embargo, esto conlleva una [alta complejidad
y carga de mantenimiento](https://bazel.build/migrate/xcode).


## Alternativas {#alternativas}

### Gestor de paquetes Swift {#swift-package-manager}

Mientras que el Gestor de Paquetes Swift (SPM) se centra principalmente en las
dependencias, Tuist ofrece un enfoque diferente. Con Tuist, no te limitas a
definir paquetes para la integración con SPM; das forma a tus proyectos
utilizando conceptos familiares como proyectos, espacios de trabajo, objetivos y
esquemas.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) es un generador de proyectos
dedicado diseñado para reducir los conflictos en los proyectos colaborativos de
Xcode y simplificar algunas complejidades del funcionamiento interno de Xcode.
Sin embargo, los proyectos se definen utilizando formatos serializables como
[YAML](https://yaml.org/). A diferencia de Swift, esto no permite a los
desarrolladores construir sobre abstracciones o comprobaciones sin incorporar
herramientas adicionales. Aunque XcodeGen ofrece una forma de asignar
dependencias a una representación interna para su validación y optimización,
sigue exponiendo a los desarrolladores a los matices de Xcode. Esto podría hacer
de XcodeGen una base adecuada para [herramientas de
construcción](https://github.com/MobileNativeFoundation/rules_xcodeproj), como
se ve en la comunidad Bazel, pero no es óptimo para la evolución de proyectos
inclusivos que tiene como objetivo mantener un ambiente sano y productivo.

### Bazel {#bazel}

[Bazel](https://bazel.build) es un sistema de construcción avanzado conocido por
sus características de caché remoto, ganando popularidad dentro de la comunidad
Swift principalmente por esta capacidad. Sin embargo, dada la limitada
extensibilidad de Xcode y su sistema de compilación, sustituirlo por el sistema
de Bazel exige un esfuerzo y un mantenimiento considerables. Sólo unas pocas
empresas con abundantes recursos pueden soportar esta sobrecarga, como se
desprende de la selecta lista de empresas que invierten fuertemente para
integrar Bazel con Xcode. Curiosamente, la comunidad creó una
[herramienta](https://github.com/MobileNativeFoundation/rules_xcodeproj) que
emplea el XcodeGen de Bazel para generar un proyecto Xcode. Esto resulta en una
enrevesada cadena de conversiones: de archivos Bazel a XcodeGen YAML y
finalmente a proyectos Xcode. Tal indirección en capas a menudo complica la
solución de problemas, haciendo que los problemas sean más difíciles de
diagnosticar y resolver.
