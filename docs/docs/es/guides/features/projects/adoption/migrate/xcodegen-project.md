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
para definir proyectos Xcode. Muchas organizaciones **la han adoptado para
intentar escapar de los frecuentes conflictos de Git que surgen al trabajar con
proyectos Xcode.** Sin embargo, los frecuentes conflictos de Git son solo uno de
los muchos problemas que experimentan las organizaciones. Xcode expone a los
desarrolladores a muchas complejidades y configuraciones implícitas que
dificultan el mantenimiento y la optimización de proyectos a gran escala.
XcodeGen se queda corto en este aspecto por su diseño, ya que es una herramienta
que genera proyectos Xcode, no un gestor de proyectos. Si necesitas una
herramienta que te ayude más allá de la generación de proyectos Xcode, quizá te
interese Tuist.

::: tip SWIFT OVER YAML
<!-- -->
Muchas organizaciones también prefieren Tuist como herramienta de generación de
proyectos porque utiliza Swift como formato de configuración. Swift es un
lenguaje de programación con el que los desarrolladores están familiarizados y
que les ofrece la comodidad de utilizar las funciones de autocompletado,
comprobación de tipos y validación de Xcode.
<!-- -->
:::

A continuación se incluyen algunas consideraciones y directrices que le ayudarán
a migrar sus proyectos de XcodeGen a Tuist.

## Generación de proyectos {#project-generation}

Tanto Tuist como XcodeGen proporcionan un comando « `» y «` » que convierte la
declaración de tu proyecto en proyectos y espacios de trabajo de Xcode.

::: grupo de códigos

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

La diferencia radica en la experiencia de edición. Con Tuist, puede ejecutar el
comando « `tuist edit` », que genera un proyecto Xcode sobre la marcha que puede
abrir y empezar a trabajar. Esto resulta especialmente útil cuando desea
realizar cambios rápidos en su proyecto.

## `project.yaml` {#projectyaml}

El archivo de descripción `project.yaml` de XcodeGen se convierte en
`Project.swift`. Además, puede tener `Workspace.swift` como una forma de
personalizar cómo se agrupan los proyectos en los espacios de trabajo. También
puede tener un proyecto `Project.swift` con objetivos que hacen referencia a
objetivos de otros proyectos. En esos casos, Tuist generará un espacio de
trabajo de Xcode que incluya todos los proyectos.

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
embargo, la configuración basada en Swift de Tuist le ofrece la comodidad de
utilizar las funciones de autocompletado, comprobación de tipos y validación de
Xcode.
<!-- -->
:::

## Plantillas de especificaciones {#spec-templates}

Una de las desventajas de YAML como lenguaje para la configuración de proyectos
es que no admite la reutilización entre archivos YAML de forma predeterminada.
Esta es una necesidad común al describir proyectos, que XcodeGen tuvo que
resolver con su propia solución propietaria denominada «plantillas» de ** . Con
Tuist, la reutilización está integrada en el propio lenguaje, Swift, y a través
de un módulo de Swift denominado
<LocalizedLink href="/guides/features/projects/code-sharing">project description
helpers</LocalizedLink>, que permite reutilizar el código en todos los archivos
de manifiesto.

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
