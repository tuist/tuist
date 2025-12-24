---
{
  "title": "Migrate an XcodeGen project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from XcodeGen to Tuist."
}
---
# Migrar un proyecto XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) es una herramienta de
generación de proyectos que utiliza YAML como [formato de
configuración](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
para definir proyectos Xcode. Muchas organizaciones **la adoptaron tratando de
escapar de los frecuentes conflictos Git que surgen al trabajar con proyectos
Xcode.** Sin embargo, los frecuentes conflictos de Git son sólo uno de los
muchos problemas que experimentan las organizaciones. Xcode expone a los
desarrolladores a un montón de complejidades y configuraciones implícitas que
dificultan el mantenimiento y la optimización de proyectos a escala. XcodeGen se
queda corto ahí por diseño, porque es una herramienta que genera proyectos
Xcode, no un gestor de proyectos. Si necesitas una herramienta que te ayude más
allá de la generación de proyectos Xcode, es posible que desees considerar
Tuist.

::: tip SWIFT OVER YAML
<!-- -->
Muchas organizaciones prefieren Tuist como herramienta de generación de
proyectos también porque utiliza Swift como formato de configuración. Swift es
un lenguaje de programación con el que los desarrolladores están familiarizados
y que les proporciona la comodidad de utilizar las funciones de autocompletado,
comprobación de tipos y validación de Xcode.
<!-- -->
:::

Lo que sigue son algunas consideraciones y directrices para ayudarte a migrar
tus proyectos de XcodeGen a Tuist.

## Generación de proyectos {#project-generation}

Tanto Tuist como XcodeGen proporcionan un comando `generate` que convierte tu
declaración de proyecto en proyectos y espacios de trabajo de Xcode.

::: grupo de códigos

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

La diferencia radica en la experiencia de edición. Con Tuist, puedes ejecutar el
comando `tuist edit`, que genera un proyecto Xcode sobre la marcha que puedes
abrir y empezar a trabajar en él. Esto es especialmente útil cuando quieres
hacer cambios rápidos en tu proyecto.

## `proyecto.yaml` {#projectyaml}

El archivo de descripción `project.yaml` de XcodeGen se convierte en
`Project.swift`. Además, puede tener `Workspace.swift` como una forma de
personalizar cómo se agrupan los proyectos en espacios de trabajo. También
puedes tener un proyecto `Project.swift` con objetivos que hagan referencia a
objetivos de otros proyectos. En esos casos, Tuist generará un Xcode Workspace
incluyendo todos los proyectos.

::: grupo de códigos

```bash [XcodeGen directory structure]
/
  project.yaml
```

```bash [Tuist directory structure]
/
  Tuist.swift
  Project.swift
  Workspace.swift
```
<!-- -->
:::

::: tip XCODE'S LANGUAGE
<!-- -->
Tanto XcodeGen como Tuist adoptan el lenguaje y los conceptos de Xcode. Sin
embargo, la configuración basada en Swift de Tuist te ofrece la comodidad de
utilizar las funciones de autocompletado, comprobación de tipos y validación de
Xcode.
<!-- -->
:::

## Plantillas de especificaciones {#spec-templates}

Una de las desventajas de YAML como lenguaje para la configuración de proyectos
es que no permite la reutilización de archivos YAML. Esta es una necesidad común
al describir proyectos, que XcodeGen tuvo que resolver con su propia solución
propietaria llamada *"templates"*. Con Tuist la reutilización está integrada en
el propio lenguaje, Swift, y a través de un módulo Swift llamado
<LocalizedLink href="/guides/features/projects/code-sharing">project description helpers</LocalizedLink>, que permite la reutilización de código en todos los
archivos de manifiesto.

::: grupo de códigos
```swift [Tuist/ProjectDescriptionHelpers/Target+Features.swift]
import ProjectDescription

extension Target {
  /**
    This function is a factory of targets that together represent a feature.
  */
  static func featureTargets(name: String) -> [Target] {
    // ...
  }
}
```
```swift [Project.swift]
import ProjectDescription
import ProjectDescriptionHelpers // [!code highlight]

let project = Project(name: "MyProject",
                      targets: Target.featureTargets(name: "MyFeature")) // [!code highlight]
```
