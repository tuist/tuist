## Métricas de la máquina {#machine-metrics}

Los análisis de compilaciones pueden incluir métricas de rendimiento a nivel de máquina (CPU, memoria, red y uso de disco) capturadas durante la compilación. Para habilitarlo, configura un demonio ligero en segundo plano que muestree continuamente las métricas del sistema:

```bash
tuist setup insights
```

Esto ejecuta un demonio local que muestrea las métricas en segundo plano. Los datos son recogidos automáticamente por `tuist inspect build` y se suben junto con el informe de compilación.

Las métricas de disco incluyen la actividad de lectura/escritura y, con una CLI y un servidor compatibles, el espacio total y disponible en el volumen de datos del sistema macOS (`/System/Volumes/Data`). El espacio disponible excluye el espacio purgable. El gráfico de espacio en disco muestra el espacio utilizado (total menos disponible) junto con la capacidad total durante la compilación, no solo en el momento de la subida. No mide volúmenes externos separados utilizados para un checkout o DerivedData.

Después de actualizar la CLI, reinicia un muestreador existente con `tuist teardown insights` seguido de `tuist setup insights`. El muestreo debe estar ejecutándose durante la compilación; los informes antiguos y las mediciones fallidas no tienen valores de espacio en disco y no se muestran como cero. Las muestras de espacio en disco siguen la retención existente de 90 días para las métricas de la máquina.

> [!TIP]
> **CI**
>
> Ejecuta `tuist setup insights` en tus máquinas de CI antes de compilar para capturar también las métricas de la máquina allí.

Para dejar de recopilar métricas de la máquina, ejecuta:

```bash
tuist teardown insights
```

Esto descarga el LaunchAgent del demonio, elimina su plist y borra las métricas muestreadas y los registros del demonio de `~/.local/state`, por lo que no queda nada ejecutándose en segundo plano.
