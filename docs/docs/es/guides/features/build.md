---
{
  "title": "Build",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to use Tuist to build your projects efficiently."
}
---
# Construir {#build}

Los proyectos se construyen normalmente a través de un CLI proporcionado por el
sistema de construcción (por ejemplo, `xcodebuild`). Tuist los envuelve para
mejorar la experiencia del usuario e integrar los flujos de trabajo con la
plataforma para proporcionar optimizaciones y análisis.

Puede que te preguntes cuál es el valor de usar `tuist build` en lugar de
generar el proyecto con `tuist generate` (si es necesario) y construirlo con la
CLI específica de la plataforma. He aquí algunas razones:

- **Comando único:** `tuist build` asegura que el proyecto se genera si es
  necesario antes de compilar el proyecto.
- **Salida embellecida:** Tuist enriquece la salida utilizando herramientas como
  [xcbeautify](https://github.com/cpisciotta/xcbeautify) que hacen que la salida
  sea más fácil de usar.
- <LocalizedLink href="/guides/features/cache"><bold>Caché:</bold></LocalizedLink>
  Optimiza la compilación reutilizando de forma determinista los artefactos de
  compilación de una caché remota.
- **Analítica:** Recopila e informa métricas que se correlacionan con otros
  puntos de datos para proporcionarle información procesable para tomar
  decisiones informadas.

## Uso {#usage}

`tuist build` genera el proyecto si es necesario, y luego lo construye
utilizando la herramienta de construcción específica de la plataforma. Apoyamos
el uso del terminador `--` para reenviar todos los argumentos subsiguientes
directamente a la herramienta de construcción subyacente. Esto es útil cuando
necesitas pasar argumentos que no son soportados por `tuist build` pero sí por
la herramienta de construcción subyacente.

::: grupo de códigos
```bash [Build a scheme]
tuist build MyScheme
```
```bash [Build a specific configuration]
tuist build MyScheme -- -configuration Debug
```
```bash [Build all schemes without binary cache]
tuist build --no-binary-cache
```
:::
