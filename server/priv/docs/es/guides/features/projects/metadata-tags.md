---
{
  "title": "Etiquetas de metadatos",
  "titleTemplate": ":title · Proyectos · Funcionalidades · Guías · Tuist",
  "description": "Aprende a usar las etiquetas de metadatos de destino para organizar y centrarte en partes específicas de tu proyecto"
}
---
# Etiquetas de metadatos {#metadata-tags}

A medida que los proyectos crecen en tamaño y complejidad, trabajar con todo el código base a la vez puede volverse ineficiente. Tuist ofrece **etiquetas de metadatos** como una forma de organizar los targets en grupos lógicos y centrarse en partes específicas de tu proyecto durante el desarrollo.

## ¿Qué son las etiquetas de metadatos? {#what-are-metadata-tags}

Las etiquetas de metadatos son cadenas de texto que puedes adjuntar a los targets de tu proyecto. Sirven como marcadores que te permiten:

- **Agrupar targets relacionados**: etiqueta los targets que pertenecen a la misma funcionalidad, equipo o capa arquitectónica
- **Enfocar tu espacio de trabajo**: genera proyectos que incluyan únicamente targets con etiquetas específicas
- **Optimizar tu flujo de trabajo**: trabaja en funcionalidades concretas sin cargar partes no relacionadas del código base
- **Seleccionar targets para mantener como fuentes**: elige qué grupo de targets quieres conservar como fuentes al usar la caché

Las etiquetas se definen mediante la propiedad `metadata` de los targets y se almacenan como un array de cadenas.

## Definir etiquetas de metadatos {#defining-metadata-tags}

Puedes añadir etiquetas a cualquier target en el manifiesto de tu proyecto:

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

## Centrarse en targets etiquetados {#focusing-on-tagged-targets}

Una vez que hayas etiquetado tus targets, puedes usar el comando `tuist generate` para crear un proyecto enfocado que incluya solo targets específicos:

### Enfocar por etiqueta

Usa el prefijo `tag:` para generar un proyecto con todos los targets que coincidan con una etiqueta concreta:

```bash
# Generate project with all authentication-related targets
tuist generate tag:feature:auth

# Generate project with all targets owned by the identity team
tuist generate tag:team:identity
```

### Enfocar por nombre

También puedes centrarte en targets específicos por su nombre:

```bash
# Generate project with the Authentication target
tuist generate Authentication
```

### Cómo funciona el enfoque

Cuando te centras en targets:

1. **Targets incluidos**: los targets que coinciden con tu consulta se incluyen en el proyecto generado
2. **Dependencias**: todas las dependencias de los targets enfocados se incluyen automáticamente
3. **Targets de tests**: se incluyen los targets de tests de los targets enfocados
4. **Exclusión**: el resto de targets se excluyen del espacio de trabajo

Esto significa que obtienes un espacio de trabajo más pequeño y manejable, que contiene solo lo necesario para trabajar en tu funcionalidad.

## Convenciones de nomenclatura de etiquetas {#tag-naming-conventions}

Aunque puedes usar cualquier cadena como etiqueta, seguir una convención de nombres consistente ayuda a mantener tus etiquetas organizadas:

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

Usar prefijos como `feature:`, `team:` o `layer:` facilita comprender el propósito de cada etiqueta y evitar conflictos de nombres.

## Etiquetas del sistema {#system-tags}

Tuist utiliza el prefijo `tuist:` para las etiquetas gestionadas por el sistema. Estas etiquetas se aplican automáticamente por Tuist y pueden usarse en perfiles de caché para apuntar a tipos específicos de contenido generado.

### Etiquetas del sistema disponibles

| Etiqueta | Descripción |
| --- | --- |
| `tuist:synthesized` | Se aplica a los targets de bundles sintetizados que Tuist crea para gestionar recursos en bibliotecas estáticas y frameworks estáticos. Estos bundles existen por razones históricas para proporcionar APIs de acceso a recursos. |

### Uso de etiquetas del sistema con perfiles de caché

Puedes usar etiquetas del sistema en los perfiles de caché para incluir o excluir targets sintetizados:

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

> [!TIP]
> **Los bundles sintetizados heredan las etiquetas del padre**
>
> Los targets de bundles sintetizados heredan todas las etiquetas de su target padre, además de recibir la etiqueta `tuist:synthesized`. Esto significa que si etiquetas una biblioteca estática con `feature:auth`, su bundle de recursos sintetizado tendrá tanto la etiqueta `feature:auth` como la `tuist:synthesized`.


## Uso de etiquetas con helpers de descripción de proyecto {#using-tags-with-helpers}

Puedes aprovechar los <.localized_link href="/guides/features/projects/code-sharing">helpers de descripción de proyecto</.localized_link> para estandarizar cómo se aplican las etiquetas en todo tu proyecto:

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

## Beneficios de usar etiquetas de metadatos {#benefits}

### Mejora la experiencia de desarrollo

Al centrarte en partes específicas de tu proyecto, puedes:

- **Reducir el tamaño del proyecto de Xcode**: trabaja con proyectos más pequeños que se abren y navegan más rápido
- **Acelerar las compilaciones**: compila solo lo necesario para tu trabajo actual
- **Mejorar el enfoque**: evita distracciones de código no relacionado
- **Optimizar la indexación**: Xcode indexa menos código, lo que hace que el autocompletado sea más rápido

### Mejor organización del proyecto

Las etiquetas ofrecen una forma flexible de organizar tu base de código:

- **Múltiples dimensiones**: etiqueta los targets por funcionalidad, equipo, capa, plataforma o cualquier otra dimensión
- **Sin cambios estructurales**: añade estructura organizativa sin cambiar la disposición de directorios
- **Preocupaciones transversales**: un único target puede pertenecer a varios grupos lógicos

### Integración con la caché

Las etiquetas de metadatos funcionan perfectamente con las <.localized_link href="/guides/features/cache">funcionalidades de caché de Tuist</.localized_link>:

```bash
# Cache all targets
tuist cache

# Focus on targets with a specific tag and use cached dependencies
tuist generate tag:feature:payment
```

## Buenas prácticas {#best-practices}

1. **Empieza sencillo**: comienza con una única dimensión de etiquetado (por ejemplo, funcionalidades) y amplía según sea necesario
2. **Sé consistente**: usa las mismas convenciones de nomenclatura en todos tus manifiestos
3. **Documenta tus etiquetas**: mantén una lista de las etiquetas disponibles y sus significados en la documentación de tu proyecto
4. **Usa helpers**: aprovecha los helpers de descripción de proyecto para estandarizar la aplicación de etiquetas
5. **Revisa periódicamente**: a medida que tu proyecto evoluciona, revisa y actualiza tu estrategia de etiquetado

## Funcionalidades relacionadas {#related-features}

- <.localized_link href="/guides/features/projects/code-sharing">Compartición de código</.localized_link>: usa helpers de descripción de proyecto para estandarizar el uso de etiquetas
- <.localized_link href="/guides/features/cache">Caché</.localized_link>: combina etiquetas con la caché para un rendimiento óptimo de compilación
- <.localized_link href="/guides/features/selective-testing">Tests selectivos</.localized_link>: ejecuta tests solo para los targets modificados
