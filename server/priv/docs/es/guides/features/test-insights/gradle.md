---
{
  "title": "Análisis de tests de Gradle",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Sigue las analíticas de tests de Gradle en el panel de Tuist para monitorizar el rendimiento de los tests."
}
---
# Análisis de tests de Gradle {#gradle-test-insights}

El plugin de Gradle de Tuist carga automáticamente los resultados de los tests después de cada ejecución de una tarea de test, lo que te permite ver el rendimiento de los tests y detectar tests inestables directamente en el panel de Tuist.

Los análisis de tests se recopilan automáticamente cuando se aplica el plugin de Gradle de Tuist; no hace falta ninguna configuración adicional más allá de la instalación inicial del plugin.

Puedes acceder a tus análisis de tests en el panel de Tuist y ver cómo evolucionan con el tiempo:

![Panel con análisis de tests](/images/guides/features/build-insights/tests-dashboard.png)

## Qué se registra {#what-is-tracked}

El plugin recopila los resultados de todas las tareas `Test` de Gradle, incluidos:
- Estado de aprobado/fallido y duración de cada caso de test
- Estructura de suites y clases de tests
- Detección de tests inestables entre ejecuciones

## Configurar el comportamiento de carga {#configure-upload-behavior}

De forma predeterminada:
- Los resultados de los tests se cargan en segundo plano para compilaciones locales.
- Los resultados de los tests se cargan en primer plano para ejecuciones de CI para evitar perder telemetría en agentes efímeros.

Puedes sobrescribir este comportamiento usando `uploadInBackground` en el bloque `tuist` de tu `settings.gradle.kts`:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Historial de Git {#git-history}

En CI, el plugin también carga el historial de commits del checkout cuando informa de una ejecución de tests: los SHA de los commits, sus padres, las fechas de los commits y la rama en la que estaban la ejecución y la rama base de su pull request. No se cargan contenidos de archivos, mensajes de commit ni autores. Esto es lo que le indica a Tuist qué commits llegaron a tu rama predeterminada, por ejemplo, los que probó una cola de merges. El plugin lee el historial que ya tiene el checkout y, cuando el checkout no tiene la rama base, solicita al remoto su último commit (`git ls-remote`). No obtiene historial.

| Variable | Efecto |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | No lee ni carga ningún historial de Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Lee solo el checkout, sin contactar con el remoto. |
