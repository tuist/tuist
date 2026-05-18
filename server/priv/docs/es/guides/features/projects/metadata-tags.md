---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Etiquetas de metadatos {#metadata-tags}

A medida que los proyectos crecen en tamaño y complejidad, trabajar con todo el
código base a la vez puede resultar ineficaz. Tuist proporciona etiquetas de
metadatos **** como una forma de organizar los objetivos en grupos lógicos y
centrarse en partes específicas de su proyecto durante el desarrollo.

## ¿Qué son las etiquetas de metadatos? {#what-are-metadata-tags}

Las etiquetas de metadatos son etiquetas de cadena que puede adjuntar a los
objetivos de su proyecto. Sirven como marcadores que le permiten:

- **Agrupar objetivos relacionados** - Etiquetar objetivos que pertenecen a la
  misma característica, equipo o capa arquitectónica.
- **Enfoque su espacio de trabajo** - Genere proyectos que incluyan sólo
  objetivos con etiquetas específicas
- **Optimice su flujo de trabajo** - Trabaje en funciones específicas sin cargar
  partes no relacionadas de su código base.
- **Seleccionar objetivos para mantener como fuentes** - Elija qué grupo de
  objetivos desea mantener como fuentes al almacenar en caché.

Las etiquetas se definen utilizando la propiedad `metadata` en los objetivos y
se almacenan como una matriz de cadenas.

## Definición de etiquetas de metadatos {#defining-metadata-tags}

Puede añadir etiquetas a cualquier objetivo de su manifiesto de proyecto:

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "Authentication",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.authentication",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:auth", "team:identity"])
        ),
        .target(
            name: "Payment",
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.payment",
            sources: ["Sources/**"],
            metadata: .metadata(tags: ["feature:payment", "team:commerce"])
        ),
        .target(
            name: "App",
            destinations: .iOS,
            product: .app,
            bundleId: "com.example.app",
            sources: ["Sources/**"],
            dependencies: [
                .target(name: "Authentication"),
                .target(name: "Payment")
            ]
        )
    ]
)
```

## Centrarse en objetivos marcados {#focusing-on-tagged-targets}

Una vez etiquetados los objetivos, puede utilizar el comando `tuist generate`
para crear un proyecto específico que incluya únicamente objetivos concretos:

### Enfoque por etiqueta

Utilice el prefijo `tag:` para generar un proyecto con todos los objetivos que
coincidan con una etiqueta específica:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Enfoque por nombre

También puede centrarse en objetivos específicos por su nombre:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Cómo funciona el enfoque

Cuando te centras en objetivos:

1. **Objetivos incluidos** - Los objetivos que coinciden con su consulta se
   incluyen en el proyecto generado.
2. **Dependencias** - Se incluyen automáticamente todas las dependencias de los
   objetivos enfocados.
3. **Objetivos de prueba** - Se incluyen objetivos de prueba para los objetivos
   enfocados
4. **Exclusión** - Todos los demás objetivos quedan excluidos del espacio de
   trabajo

Esto significa que dispones de un espacio de trabajo más pequeño y manejable que
contiene sólo lo que necesitas para trabajar en tu reportaje.

## Convenciones de denominación de etiquetas {#tag-naming-conventions}

Aunque se puede utilizar cualquier cadena como etiqueta, seguir una convención
de nomenclatura coherente ayuda a mantener las etiquetas organizadas:

```swift
// Organize by feature
metadata: .metadata(tags: ["feature:authentication", "feature:payment"])

// Organize by team ownership
metadata: .metadata(tags: ["team:identity", "team:commerce"])

// Organize by architectural layer
metadata: .metadata(tags: ["layer:ui", "layer:business", "layer:data"])

// Organize by platform
metadata: .metadata(tags: ["platform:ios", "platform:macos"])

// Combine multiple dimensions
metadata: .metadata(tags: ["feature:auth", "team:identity", "layer:ui"])
```

El uso de prefijos como `feature:`, `team:`, o `layer:` facilita la comprensión
del propósito de cada etiqueta y evita conflictos de nomenclatura.

## Utilización de etiquetas con los asistentes de descripción de proyectos {#using-tags-with-helpers}

Puede utilizar <LocalizedLink href="/guides/features/projects/code-sharing">ayudantes de descripción de proyectos</LocalizedLink> para estandarizar cómo se aplican las etiquetas en todo el proyecto:

```swift
// Tuist/ProjectDescriptionHelpers/Project+Templates.swift
import ProjectDescription

extension Target {
    public static func feature(
        name: String,
        team: String,
        dependencies: [TargetDependency] = []
    ) -> Target {
        .target(
            name: name,
            destinations: .iOS,
            product: .framework,
            bundleId: "com.example.\(name.lowercased())",
            sources: ["Sources/**"],
            dependencies: dependencies,
            metadata: .metadata(tags: [
                "feature:\(name.lowercased())",
                "team:\(team.lowercased())"
            ])
        )
    }
}
```

Luego úsalo en tus manifiestos:

```swift
import ProjectDescription
import ProjectDescriptionHelpers

let project = Project(
    name: "Features",
    targets: [
        .feature(name: "Authentication", team: "Identity"),
        .feature(name: "Payment", team: "Commerce"),
    ]
)
```

## Ventajas de utilizar etiquetas de metadatos {#benefits}

### Experiencia de desarrollo mejorada

Si te centras en partes concretas de tu proyecto, podrás:

- **Reduzca el tamaño de los proyectos de Xcode** - Trabaje con proyectos más
  pequeños que son más rápidos de abrir y navegar.
- **Acelera las construcciones** - Construye sólo lo que necesitas para tu
  trabajo actual
- **Mejorar la concentración** - Evitar distracciones de código no relacionado
- **Optimizar la indexación** - Xcode indexa menos código, haciendo más rápido
  el autocompletado.

### Mejor organización del proyecto

Las etiquetas permiten organizar el código de forma flexible:

- **Múltiples dimensiones** - Etiquetar objetivos por característica, equipo,
  capa, plataforma o cualquier otra dimensión.
- **Sin cambios estructurales** - Añada estructura organizativa sin cambiar el
  diseño del directorio
- **Preocupaciones transversales** - Un mismo objetivo puede pertenecer a varios
  grupos lógicos

### Integración con la caché

Las etiquetas de metadatos funcionan a la perfección con las funciones de <LocalizedLink href="/guides/features/cache">almacenamiento en caché de Tuist</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Buenas prácticas {#best-practices}

1. **Inicio sencillo** - Comience con una única dimensión de etiquetado (por
   ejemplo, características) y amplíela según sea necesario.
2. **Sea coherente** - Utilice las mismas convenciones de nomenclatura en todos
   sus manifiestos.
3. **Documente sus etiquetas** - Mantenga una lista de las etiquetas disponibles
   y sus significados en la documentación de su proyecto.
4. **Use helpers** - Aproveche los helpers de descripción de proyectos para
   estandarizar la aplicación de etiquetas
5. **Revise periódicamente** - A medida que evolucione su proyecto, revise y
   actualice su estrategia de etiquetado.

## Funciones relacionadas {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Compartir código</LocalizedLink> - Utilizar ayudantes de descripción de proyectos para estandarizar el uso de etiquetas
- <LocalizedLink href="/guides/features/cache">Caché</LocalizedLink> - Combine las etiquetas con la caché para obtener un rendimiento óptimo de la compilación
- <LocalizedLink href="/guides/features/selective-testing">Pruebas selectivas</LocalizedLink> - Ejecutar pruebas sólo para los objetivos modificados
