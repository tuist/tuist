---
{
  "title": "Depuración",
  "titleTemplate": ":title · Contribuidores · Tuist",
  "description": "Usa agentes de programación y ejecuciones locales para depurar problemas en Tuist."
}
---
# Depuración {#debugging}

Ser abierto es una ventaja práctica: el código está disponible, puedes ejecutarlo localmente y puedes usar agentes de programación para responder preguntas más rápido y depurar posibles errores en la base de código.

Si encuentras documentación faltante o incompleta mientras depuras, actualiza la documentación en inglés en `docs/` y abre un PR.

## Capturar volcados de hilos en CI {#thread-dump-ci}

Cuando la CLI se cuelga intermitentemente, puedes capturar un volcado de hilos sin detener el proceso. Habilita el manejador de señales y envía `SIGUSR1` al proceso `tuist` en ejecución.

```bash
export TUIST_THREAD_DUMP_SIGNAL=1
export TUIST_THREAD_DUMP_SAMPLE=1 # macOS only, captures all threads via /usr/bin/sample
tuist generate &
TUIST_PID=$!
sleep 600
kill -USR1 "$TUIST_PID"
wait "$TUIST_PID"
```

Si `TUIST_THREAD_DUMP_SAMPLE` no está configurado, el manejador imprime la pila del hilo actual. La salida se escribe en stderr, por lo que aparece en los registros de CI.

## Usar agentes de programación {#use-coding-agents}

Los agentes de programación son útiles para:

- Escanear la base de código para encontrar dónde se implementa un comportamiento.
- Reproducir problemas localmente e iterar rápidamente.
- Rastrear cómo fluyen las entradas a través de Tuist para encontrar la causa raíz.

Comparte la reproducción más pequeña que puedas y dirige al agente al componente específico (CLI, servidor, caché, documentación o manual). Cuanto más enfocado sea el alcance, más rápido y preciso será el proceso de depuración.

### Indicaciones frecuentemente necesarias (FNP) {#frequently-needed-prompts}

#### Generación de proyecto inesperada {#unexpected-project-generation}

La generación del proyecto me está dando algo que no espero. Ejecuta la CLI de Tuist contra mi proyecto en `/path/to/project` para entender por qué está ocurriendo esto. Rastrea la tubería del generador e indica las rutas de código responsables del resultado.

#### Error reproducible en proyectos generados {#reproducible-bug-in-generated-projects}

Esto parece un error en los proyectos generados. Crea un proyecto reproducible en `examples/`, usando ejemplos existentes como referencia. Añade una prueba de aceptación que falle, ejecútala mediante `xcodebuild` seleccionando solo esa prueba, corrige el problema, vuelve a ejecutar la prueba para confirmar que pasa y abre un PR.
