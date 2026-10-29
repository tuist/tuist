---
{
  "title": "Depuración",
  "titleTemplate": ":title · Colaboradores · Tuist",
  "description": "Usa agentes de programación y ejecuciones locales para depurar problemas en Tuist."
}
---
# Depuración {#debugging}

Ser abierto es una ventaja práctica: el código está disponible, puedes ejecutarlo localmente y puedes usar agentes de programación para responder preguntas más rápido y depurar posibles errores en la base de código.

Si encuentras documentación faltante o incompleta mientras depuras, actualiza la documentación en inglés bajo `docs/` y abre un PR.

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

Si `TUIST_THREAD_DUMP_SAMPLE` no está establecido, el manejador imprime la pila del hilo actual. La salida se escribe en stderr, por lo que aparece en los registros de CI.

## Usar agentes de programación {#use-coding-agents}

Los agentes de programación son útiles para:

- Escanear la base de código para ver dónde se implementa un comportamiento.
- Reproducir problemas localmente e iterar rápidamente.
- Rastrear cómo fluyen las entradas a través de Tuist para encontrar la causa raíz.

Comparte la reproducción más pequeña posible y dirige al agente hacia el componente específico (CLI, servidor, caché, docs o handbook). Cuanto más enfocado sea el alcance, más rápido y preciso será el proceso de depuración.

### Prompts frecuentemente necesarios (FNP) {#frequently-needed-prompts}

#### Generación de proyecto inesperada {#unexpected-project-generation}

La generación del proyecto me está dando algo que no espero. Ejecuta la CLI de Tuist contra mi proyecto en `/path/to/project` para entender por qué está ocurriendo esto. Rastrea el pipeline del generador y señala las rutas de código responsables del resultado.

#### Error reproducible en proyectos generados {#reproducible-bug-in-generated-projects}

Esto parece un error en los proyectos generados. Crea un proyecto reproducible bajo `examples/`, usando ejemplos existentes como referencia. Añade un test de aceptación que falle, ejecútalo mediante `xcodebuild` con solo ese test seleccionado, corrige el problema, vuelve a ejecutar el test para confirmar que pasa y abre un PR.
