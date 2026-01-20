---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist and Xcode projects."
}
---
# Buenas prácticas {#best-practices}

A lo largo de los años trabajando con diferentes equipos y proyectos, hemos
identificado un conjunto de buenas prácticas que recomendamos seguir cuando se
trabaja con proyectos Tuist y Xcode. Estas prácticas no son obligatorias, pero
pueden ayudarte a estructurar tus proyectos de forma que sean más fáciles de
mantener y escalar.

## Xcode {#xcode}

### Patrones desalentadores {#discouraged-patterns}

#### Configuraciones para modelar entornos remotos {#configurations-to-model-remote-environments}

Muchas organizaciones utilizan configuraciones de compilación para modelar
diferentes entornos remotos (por ejemplo, `Debug-Production` o
`Release-Canary`), pero este enfoque tiene algunas desventajas:

- **Inconsistencias:** Si hay incoherencias de configuración en todo el gráfico,
  el sistema de compilación puede acabar utilizando la configuración incorrecta
  para algunos objetivos.
- **Complejidad:** Los proyectos pueden acabar con una larga lista de
  configuraciones locales y entornos remotos difíciles de razonar y mantener.

Las configuraciones de compilación se diseñaron para incorporar diferentes
configuraciones de compilación, y los proyectos rara vez necesitan más que
`Debug` y `Release`. La necesidad de modelar diferentes entornos puede lograrse
de diferentes maneras:

- **En construcciones Debug:** Puedes incluir en la app todas las
  configuraciones que deberían ser accesibles en desarrollo (por ejemplo,
  endpoints), y cambiarlas en tiempo de ejecución. El cambio se puede realizar
  mediante variables de entorno de lanzamiento o con una interfaz de usuario
  dentro de la aplicación.
- **En compilaciones Release:** En caso de lanzamiento, sólo puede incluir la
  configuración a la que está vinculada la compilación de lanzamiento, y no
  incluir la lógica de tiempo de ejecución para cambiar las configuraciones
  mediante el uso de directivas del compilador.

::: info Configuraciones no estándar
<!-- -->
Aunque Tuist admite configuraciones no estándar y las hace más fáciles de
gestionar en comparación con los proyectos Xcode estándar, recibirás
advertencias si las configuraciones no son coherentes en todo el gráfico de
dependencias. Esto ayuda a garantizar la fiabilidad de la compilación y evita
problemas relacionados con la configuración.
<!-- -->
:::

## Proyectos generados

### Carpetas construibles

Tuist 4.62.0 añadido soporte para **carpetas construibles** (grupos
sincronizados de Xcode), una característica introducida en Xcode 16 para reducir
los conflictos de fusión.

Aunque los patrones comodín de Tuist (por ejemplo, `Sources/**/*.swift`) ya
eliminan los conflictos de fusión en los proyectos generados, las carpetas
construibles ofrecen ventajas adicionales:

- **Sincronización automática**: La estructura del proyecto se mantiene
  sincronizada con el sistema de archivos, sin necesidad de regeneración al
  añadir o eliminar archivos.
- **Flujos de trabajo compatibles con IA**: Los asistentes y agentes de
  codificación pueden modificar su código base sin provocar la regeneración del
  proyecto.
- **Configuración más sencilla**: Definir rutas de carpetas en lugar de
  gestionar listas explícitas de archivos.

Recomendamos adoptar carpetas compilables en lugar de los atributos
tradicionales `Target.sources` y `Target.resources` para una experiencia de
desarrollo más ágil.

::: grupo de códigos

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### Dependencias

#### Forzar versiones resueltas en CI

Cuando instale dependencias del Gestor de Paquetes Swift en CI, le recomendamos
que utilice la opción `--force-resolved-versions` para garantizar compilaciones
deterministas:

```bash
tuist install --force-resolved-versions
```

Esta bandera asegura que las dependencias se resuelven utilizando las versiones
exactas fijadas en `Package.resolved`, eliminando los problemas causados por el
no determinismo en la resolución de dependencias. Esto es particularmente
importante en CI, donde las compilaciones reproducibles son críticas.
