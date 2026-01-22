---
{
  "title": "Metadata tags",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to use target metadata tags to organize and focus on specific parts of your project"
}
---
# Etiquetas de metadatos {#metadata-tags}

A medida que los proyectos crecen en tamaño y complejidad, trabajar con todo el
código a la vez puede resultar ineficaz. Tuist proporciona etiquetas de
metadatos **** como una forma de organizar los objetivos en grupos lógicos y
centrarse en partes específicas de tu proyecto durante el desarrollo.

## ¿Qué son las etiquetas de metadatos? {#what-are-metadata-tags}

Las etiquetas de metadatos son etiquetas de cadena que puede adjuntar a los
objetivos de su proyecto. Sirven como marcadores que le permiten:

- **Agrupa los objetivos relacionados** - Etiqueta los objetivos que pertenecen
  a la misma característica, equipo o capa arquitectónica.
- **Céntrate en tu espacio de trabajo** - Genera proyectos que incluyan solo
  objetivos con etiquetas específicas.
- **Optimice su flujo de trabajo c** - Trabaje en funciones específicas sin
  cargar partes no relacionadas de su código base.
- **Selecciona los destinos que deseas conservar como fuentes** - Elige qué
  grupo de destinos deseas conservar como fuentes al almacenar en caché.

Las etiquetas se definen utilizando la propiedad` de metadatos `en los destinos
y se almacenan como una matriz de cadenas.

## Definición de etiquetas de metadatos {#defining-metadata-tags}

Puedes añadir etiquetas a cualquier destino en el manifiesto de tu proyecto:

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

## Centrarse en los objetivos etiquetados {#focusing-on-tagged-targets}

Una vez que hayas etiquetado tus objetivos, puedes utilizar el comando « `tuist
generate` » para crear un proyecto específico que incluya solo objetivos
concretos:

### Enfoque por etiqueta

Utilice la etiqueta `: prefijo` para generar un proyecto con todos los objetivos
que coincidan con una etiqueta específica:

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

Cuando te centres en los objetivos:

1. **Objetivos incluidos** - Los objetivos que coinciden con su consulta se
   incluyen en el proyecto generado.
2. **Dependencias** - Todas las dependencias de los objetivos seleccionados se
   incluyen automáticamente.
3. **Objetivos de prueba** - Se incluyen los objetivos de prueba para los
   objetivos enfocados.
4. **Exclusión** - Todos los demás destinos se excluyen del espacio de trabajo.

Esto significa que obtienes un espacio de trabajo más pequeño y manejable que
contiene solo lo que necesitas para trabajar en tu función.

## Convenciones de nomenclatura de etiquetas {#tag-naming-conventions}

Aunque puedes utilizar cualquier cadena como etiqueta, seguir una convención de
nomenclatura coherente te ayudará a mantener tus etiquetas organizadas:

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

El uso de prefijos como `feature:`, `team:` o `layer:` facilita la comprensión
del propósito de cada etiqueta y evita conflictos de nomenclatura.

## Etiquetas del sistema {#system-tags}

Tuist utiliza el prefijo `tuist:` para las etiquetas gestionadas por el sistema.
Estas etiquetas son aplicadas automáticamente por Tuist y pueden utilizarse en
los perfiles de caché para dirigir tipos específicos de contenido generado.

### Etiquetas de sistema disponibles

| Etiqueta            | Descripción                                                                                                                                                                                                                          |
| ------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `tuist:synthesized` | Se aplica a los objetivos de paquetes sintetizados que Tuist crea para la gestión de recursos en bibliotecas estáticas y marcos estáticos. Estos paquetes existen por razones históricas para proporcionar API de acceso a recursos. |

### Uso de etiquetas del sistema con perfiles de caché

Puedes utilizar etiquetas del sistema en los perfiles de caché para incluir o
excluir destinos sintetizados:

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        cacheOptions: .options(
            profiles: .profiles(
                [
                    "development": .profile(
                        .onlyExternal,
                        and: ["tag:tuist:synthesized"]  // Also cache synthesized bundles
                    )
                ],
                default: .onlyExternal
            )
        )
    )
)
```

::: tip SYNTHESIZED BUNDLES INHERIT PARENT TAGS
<!-- -->
Los objetivos de paquetes sintetizados heredan todas las etiquetas de su
objetivo principal, además de recibir la etiqueta `tuist:synthesized`. Esto
significa que si etiquetas una biblioteca estática con `feature:auth`, su
paquete de recursos sintetizado tendrá las etiquetas `feature:auth` y
`tuist:synthesized`.
<!-- -->
:::

## Uso de etiquetas con ayudantes de descripción del proyecto {#using-tags-with-helpers}

Puedes aprovechar
<LocalizedLink href="/guides/features/projects/code-sharing">los ayudantes de
descripción del proyecto</LocalizedLink> para estandarizar la forma en que se
aplican las etiquetas en todo tu proyecto:

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

A continuación, utilízalo en tus manifiestos:

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

### Experiencia de desarrollo mejorada.

Al centrarte en partes específicas de tu proyecto, puedes:

- **Reducir el tamaño del proyecto Xcode** - Trabaja con proyectos más pequeños
  que se abren y navegan más rápido.
- **Acelera las compilaciones** - Compila solo lo que necesitas para tu trabajo
  actual.
- **Mejorar el enfoque** - Evitar distracciones de código no relacionado.
- **Optimizar la indexación** - Xcode indexa menos código, lo que agiliza la
  autocompletación.

### Mejor organización del proyecto.

Las etiquetas proporcionan una forma flexible de organizar tu código base:

- **Múltiples dimensiones** - Etiqueta los objetivos por característica, equipo,
  capa, plataforma o cualquier otra dimensión.
- **Sin cambios estructurales** - Añade estructura organizativa sin cambiar el
  diseño del directorio.
- **Aspectos transversales** - Un único objetivo puede pertenecer a varios
  grupos lógicos.

### Integración con el almacenamiento en caché

Las etiquetas de metadatos funcionan a la perfección con
<LocalizedLink href="/guides/features/cache">las funciones de almacenamiento en
caché de Tuist</LocalizedLink>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Buenas prácticas {#best-practices}

1. **Empieza por lo sencillo** - Comienza con una sola dimensión de etiquetado
   (por ejemplo, características) y amplía según sea necesario.
2. **Sé coherente** - Utiliza las mismas convenciones de nomenclatura en todos
   tus manifiestos.
3. **Documenta tus etiquetas** - Mantén una lista de las etiquetas disponibles y
   sus significados en la documentación de tu proyecto.
4. **Utiliza las ayudas** - Aprovecha las ayudas de descripción del proyecto
   para estandarizar la aplicación de etiquetas.
5. **Revisa periódicamente** - A medida que tu proyecto evolucione, revisa y
   actualiza tu estrategia de etiquetado.

## Funciones relacionadas {#related-features}

- <LocalizedLink href="/guides/features/projects/code-sharing">Compartir
  código</LocalizedLink> - Utiliza las ayudas de descripción del proyecto para
  estandarizar el uso de etiquetas.
- <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink> - Combina
  las etiquetas con el almacenamiento en caché para obtener un rendimiento
  óptimo de la compilación.
- <LocalizedLink href="/guides/features/selective-testing">Pruebas
  selectivas</LocalizedLink> - Ejecuta pruebas solo para los objetivos
  modificados.
