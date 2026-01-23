---
{
  "title": "Debugging",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Use coding agents and local runs to debug issues in Tuist."
}
---
# Depuración {#debugging}

Ser abierto es una ventaja práctica: el código está disponible, se puede
ejecutar localmente y se pueden utilizar agentes de codificación para responder
a las preguntas más rápidamente y depurar posibles errores en el código base.

Si encuentras documentación incompleta o que falta durante la depuración,
actualiza los documentos en inglés en `docs/` y abre una solicitud de
incorporación de cambios.

## Utiliza agentes de codificación. {#use-coding-agents}

Los agentes de codificación son útiles para:

- Escanear el código base para encontrar dónde se implementa un comportamiento.
- Reproducir los problemas localmente y repetir rápidamente.
- Rastrear cómo fluyen las entradas a través de Tuist para encontrar la causa
  raíz.

Comparte la reproducción más pequeña que puedas y señala al agente el componente
específico (CLI, servidor, caché, documentación o manual). Cuanto más específico
sea el alcance, más rápido y preciso será el proceso de depuración.

### Indicaciones frecuentes (FNP) {#frequently-needed-prompts}

#### Generación inesperada de proyectos {#unexpected-project-generation}

La generación del proyecto me está dando algo que no espero. Ejecute la CLI de
Tuist en mi proyecto en `/path/to/project` para comprender por qué ocurre esto.
Rastree el proceso del generador y señale las rutas de código responsables de la
salida.

#### Error reproducible en proyectos generados. {#reproducible-bug-in-generated-projects}

Esto parece un error en los proyectos generados. Crea un proyecto reproducible
en `examples/`, utilizando los ejemplos existentes como referencia. Añade una
prueba de aceptación que falle, ejecútala a través de `xcodebuild` con solo esa
prueba seleccionada, corrige el problema, vuelve a ejecutar la prueba para
confirmar que pasa y abre una PR.
