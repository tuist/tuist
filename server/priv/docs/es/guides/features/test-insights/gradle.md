---
{
  "title": "Gradle Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Gradle test analytics in the Tuist dashboard to monitor test performance."
}
---
# Información de tests de Gradle {#gradle-test-insights}

El plugin de Gradle de Tuist carga automáticamente los resultados de los tests después de cada ejecución de una tarea de test, lo que te permite ver el rendimiento de los tests y los tests inestables directamente en el dashboard de Tuist.

La información de los tests se recopila automáticamente cuando se aplica el plugin de Gradle de Tuist; no se necesita configuración adicional más allá de la configuración inicial del plugin.

Puedes acceder a la información de tus tests en el dashboard de Tuist y ver cómo evoluciona con el tiempo:

![Dashboard con información de tests](/images/guides/features/build-insights/tests-dashboard.png)

## Qué se rastrea {#what-is-tracked}

El plugin recopila los resultados de todas las tareas `Test` de Gradle, incluyendo:
- Estado de éxito/fallo y duración de cada caso de test individual
- Estructura de suites y clases de tests
- Detección de tests inestables entre ejecuciones

## Configurar el comportamiento de carga {#configure-upload-behavior}

Por defecto:
- Los resultados de los tests se cargan en segundo plano para compilaciones locales.
- Los resultados de los tests se cargan en primer plano para ejecuciones de CI para evitar perder telemetría en agentes de corta duración.

Puedes anular este comportamiento usando `uploadInBackground` en el bloque `tuist` de tu `settings.gradle.kts`:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Historial de Git {#git-history}

En CI, el plugin también carga el historial de commits del checkout cuando informa de una ejecución de test: SHAs de commits, sus padres, fechas de commit y la rama en la que estaba la ejecución y la rama base de su pull request. No se cargan contenidos de archivos, mensajes de commit ni autores. Esto es lo que le indica a Tuist qué commits llegaron a tu rama por defecto, por ejemplo, los que probó una cola de merge. El plugin lee el historial que ya tiene el checkout y, cuando el checkout no tiene la rama base, solicita al remoto su último commit (`git ls-remote`). No obtiene el historial.

| Variable | Efecto |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | No lee ni carga ningún historial de Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Lee solo el checkout, sin contactar con el remoto. |
