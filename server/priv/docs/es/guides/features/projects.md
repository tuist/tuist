---
{
  "title": "Proyectos",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Describe proyectos de Xcode en Swift y genéralos de forma consistente con Tuist. Elimina conflictos de fusión, modela las dependencias como un grafo y desbloquea la caché de módulos."
}
---
# Proyectos generados {#generated-projects}

Los proyectos generados de Tuist son una alternativa viable que ayuda a superar estos desafíos manteniendo la complejidad y los costes en un nivel aceptable. Considera los proyectos de Xcode como un elemento fundamental, garantizando resiliencia ante futuras actualizaciones de Xcode, y aprovecha la generación de proyectos de Xcode para proporcionar a los equipos una API declarativa centrada en la modularización. Tuist utiliza la declaración del proyecto para simplificar las complejidades de la modularización, optimizar flujos de trabajo como la compilación o las pruebas en distintos entornos, y facilitar y democratizar la evolución de los proyectos de Xcode.

## ¿Cómo funciona? {#how-does-it-work}

Para empezar con los proyectos generados, solo necesitas definir tu proyecto mediante el **Lenguaje Específico del Dominio (DSL) de Tuist**. Esto implica usar archivos de manifiesto como `Workspace.swift` o `Project.swift`. Si has trabajado antes con Swift Package Manager, el enfoque es muy similar.

Una vez definido tu proyecto, Tuist ofrece varios flujos de trabajo para gestionarlo e interactuar con él:

- **Generar:** Este es un flujo de trabajo fundamental. Úsalo para crear un proyecto de Xcode compatible con Xcode.
- **<.localized_link href="/cli/build">Compilar</.localized_link>:** Este flujo de trabajo no solo genera el proyecto de Xcode, sino que también emplea `xcodebuild` para compilarlo.
- **<.localized_link href="/cli/test">Probar</.localized_link>:** Funciona de forma muy similar al flujo de compilación: no solo genera el proyecto de Xcode, sino que utiliza `xcodebuild` para probarlo.

## Desafíos con los proyectos de Xcode {#challenges-with-xcode-projects}

A medida que los proyectos de Xcode crecen, **las organizaciones pueden experimentar una caída de productividad** debido a varios factores, entre ellos compilaciones incrementales poco fiables, el borrado frecuente de la caché global de Xcode por parte de desarrolladores que se encuentran con problemas y configuraciones de proyecto frágiles. Para mantener un desarrollo rápido de funcionalidades, las organizaciones suelen explorar diversas estrategias.

Algunas organizaciones optan por evitar el compilador abstrayendo la plataforma mediante entornos de ejecución dinámicos basados en JavaScript, como [React Native](https://reactnative.dev/). Aunque este enfoque puede ser eficaz, [complica el acceso a las funcionalidades nativas de la plataforma](https://shopify.engineering/building-app-clip-react-native). Otras organizaciones optan por **modularizar la base de código**, lo que ayuda a establecer límites claros, facilita el trabajo con la base de código y mejora la fiabilidad de los tiempos de compilación. Sin embargo, el formato de proyecto de Xcode no está diseñado para la modularización y da lugar a configuraciones implícitas que pocos entienden y a conflictos frecuentes. Esto provoca un factor de bus bajo y, aunque las compilaciones incrementales puedan mejorar, los desarrolladores siguen limpiando con frecuencia la caché de compilación de Xcode (es decir, los datos derivados) cuando las compilaciones fallan. Para abordarlo, algunas organizaciones deciden **abandonar el sistema de compilación de Xcode** y adoptar alternativas como [Buck](https://buck.build/) o [Bazel](https://bazel.build/). No obstante, esto conlleva una [alta complejidad y una elevada carga de mantenimiento](https://bazel.build/migrate/xcode).


## Alternativas {#alternatives}

### Swift Package Manager {#swift-package-manager}

Mientras que Swift Package Manager (SPM) se centra principalmente en las dependencias, Tuist ofrece un enfoque diferente. Con Tuist, no solo defines paquetes para la integración con SPM; también das forma a tus proyectos usando conceptos familiares como proyectos, espacios de trabajo, destinos y esquemas.

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) es un generador de proyectos específico diseñado para reducir conflictos en proyectos de Xcode colaborativos y simplificar algunas complejidades del funcionamiento interno de Xcode. Sin embargo, los proyectos se definen mediante formatos serializables como [YAML](https://yaml.org/). A diferencia de Swift, esto no permite a los desarrolladores construir sobre abstracciones o comprobaciones sin incorporar herramientas adicionales. Aunque XcodeGen ofrece una forma de mapear dependencias a una representación interna para validación y optimización, sigue exponiendo a los desarrolladores a los matices de Xcode. Esto puede convertir a XcodeGen en una base adecuada para [construir herramientas](https://github.com/MobileNativeFoundation/rules_xcodeproj), como se observa en la comunidad de Bazel, pero no es óptimo para una evolución inclusiva del proyecto que busque mantener un entorno saludable y productivo.

### Bazel {#bazel}

[Bazel](https://bazel.build) es un sistema de compilación avanzado conocido por sus funcionalidades de caché remota, y ha ganado popularidad en la comunidad de Swift principalmente por esta capacidad. Sin embargo, dada la limitada extensibilidad de Xcode y su sistema de compilación, sustituirlo por el sistema de Bazel exige un esfuerzo y un mantenimiento considerables. Solo unas pocas empresas con recursos abundantes pueden asumir esta sobrecarga, como muestra la reducida lista de firmas que invierten mucho para integrar Bazel con Xcode. Curiosamente, la comunidad creó una [herramienta](https://github.com/MobileNativeFoundation/rules_xcodeproj) que emplea el XcodeGen de Bazel para generar un proyecto de Xcode. Esto da lugar a una cadena enrevesada de conversiones: de archivos de Bazel a YAML de XcodeGen y, finalmente, a proyectos de Xcode. Esta indirección por capas suele complicar la resolución de problemas, haciendo que los incidentes sean más difíciles de diagnosticar y resolver.
