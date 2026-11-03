---
{
  "title": "Migrar un proyecto de XcodeGen",
  "titleTemplate": ":title · Migración · Adopción · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a migrar tus proyectos de XcodeGen a Tuist."
}
---
# Migrar un proyecto de XcodeGen {#migrate-an-xcodegen-project}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) es una herramienta de generación de proyectos que utiliza YAML como [formato de configuración](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md) para definir proyectos de Xcode. Muchas organizaciones **lo adoptaron intentando evitar los frecuentes conflictos de Git que surgen al trabajar con proyectos de Xcode.** Sin embargo, los frecuentes conflictos de Git son solo uno de los muchos problemas que experimentan las organizaciones. Xcode expone a los desarrolladores a muchas complejidades y configuraciones implícitas que dificultan el mantenimiento y la optimización de proyectos a gran escala. XcodeGen se queda corto en ese aspecto por diseño, ya que es una herramienta que genera proyectos de Xcode, no un gestor de proyectos. Si necesitas una herramienta que te ayude más allá de generar proyectos de Xcode, deberías considerar Tuist.

> [!TIP]
> **Swift frente a YAML**
>
> Muchas organizaciones también prefieren Tuist como herramienta de generación de proyectos porque utiliza Swift como formato de configuración. Swift es un lenguaje de programación familiar para los desarrolladores, que les ofrece la comodidad de usar las funciones de autocompletado, comprobación de tipos y validación de Xcode.


A continuación se presentan algunas consideraciones y directrices para ayudarte a migrar tus proyectos de XcodeGen a Tuist.

## Generación de proyectos {#project-generation}

Tanto Tuist como XcodeGen ofrecen un comando `generate` que convierte la declaración de tu proyecto en proyectos y espacios de trabajo de Xcode.

::: code-group

```bash [XcodeGen]
xcodegen generate
```

```bash [Tuist]
tuist generate
```
<!-- -->
:::

La diferencia radica en la experiencia de edición. Con Tuist, puedes ejecutar el comando `tuist edit`, que genera un proyecto de Xcode al vuelo que puedes abrir y empezar a modificar. Esto es especialmente útil cuando quieres realizar cambios rápidos en tu proyecto.

## `project.yaml` {#projectyaml}

El archivo de descripción `project.yaml` de XcodeGen se convierte en `Project.swift`. Además, puedes tener `Workspace.swift` para personalizar cómo se agrupan los proyectos en espacios de trabajo. También puedes tener un `Project.swift` con destinos que hacen referencia a destinos de otros proyectos. En esos casos, Tuist generará un espacio de trabajo de Xcode que incluye todos los proyectos.

::: code-group

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

> [!TIP]
> **Lenguaje de Xcode**
>
> Tanto XcodeGen como Tuist adoptan el lenguaje y los conceptos de Xcode. Sin embargo, la configuración basada en Swift de Tuist te ofrece la comodidad de usar las funciones de autocompletado, comprobación de tipos y validación de Xcode.


## Plantillas de especificaciones {#spec-templates}

Una de las desventajas de YAML como lenguaje para la configuración de proyectos es que no admite la reutilización entre archivos YAML de forma nativa. Esta es una necesidad común al describir proyectos, que XcodeGen tuvo que resolver con su propia solución propietaria llamada *"plantillas"*. Con Tuist, la reutilización está integrada en el propio lenguaje, Swift, y a través de un módulo de Swift llamado <.localized_link href="/guides/features/projects/code-sharing">ayudantes de descripción de proyecto</.localized_link>, que permiten reutilizar código en todos tus archivos de manifiesto.

::: code-group
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
