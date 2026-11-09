## Métricas de la máquina {#machine-metrics}

Los análisis de compilaciones pueden incluir métricas de rendimiento a nivel de máquina (CPU, memoria, red y uso de disco) capturadas durante la compilación. Para habilitarlo, configura un demonio ligero en segundo plano que tome muestras continuas de las métricas del sistema:

```bash
tuist setup insights
```

Esto ejecuta un demonio local que toma muestras de métricas en segundo plano. Los datos son recogidos automáticamente por `tuist inspect build` y se suben junto con el informe de compilación.

> [!TIP]
> **CI**
>
> Ejecuta `tuist setup insights` en tus máquinas de CI antes de compilar para capturar también las métricas de la máquina allí.

Para dejar de recopilar métricas de la máquina, ejecuta:

```bash
tuist teardown insights
```

Esto descarga el LaunchAgent del demonio, elimina su plist y borra las métricas muestreadas y los registros del demonio de `~/.local/state`, de modo que no quede nada ejecutándose en segundo plano.
