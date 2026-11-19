---
{
  "title": "Análisis de tests de Gradle",
  "titleTemplate": ":title · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Supervisa las métricas de tests de Gradle en el panel de Tuist para monitorizar el rendimiento de los tests."
}
---
# Análisis de tests de Gradle {#gradle-test-insights}

> [!IMPORTANT]
> **Requisitos**
>
> - El plugin de Gradle `dev.tuist` aplicado, como se describe en <.localized_link href="/guides/get-started/gradle-project">Comenzar con un proyecto de Gradle</.localized_link>.

El plugin de Gradle de Tuist sube automáticamente los resultados de los tests después de cada ejecución de una tarea de test, ofreciéndote visibilidad sobre el rendimiento de los tests y los tests inestables directamente en el dashboard de Tuist.

Los análisis de tests se recopilan automáticamente una vez que se aplica el plugin. No es necesaria ninguna configuración adicional.

Puedes acceder a tus análisis de tests en el dashboard de Tuist y ver cómo evolucionan con el tiempo:

![Dashboard con análisis de tests](/images/guides/features/build-insights/tests-dashboard.png)

## Qué se registra {#what-is-tracked}

El plugin recopila resultados de todas las tareas `Test` de Gradle, incluyendo:
- Estado de aprobación/fallo y duración de cada caso de test
- Estructura de suites y clases de tests
- Detección de tests inestables entre ejecuciones

Activa la <.localized_link href="/guides/features/test-code-coverage/gradle">cobertura de código</.localized_link> para subir también qué código ejecutaron tus tests.

## Configurar el comportamiento de subida {#configure-upload-behavior}

Por defecto:
- Los resultados de los tests se suben en segundo plano para compilaciones locales.
- Los resultados de los tests se suben en primer plano para ejecuciones de CI para evitar perder telemetría en agentes de vida corta.

Puedes sobrescribir este comportamiento usando `uploadInBackground` en el bloque `tuist` de tu `settings.gradle.kts`:

```kotlin
tuist {
    uploadInBackground = false // always upload in the foreground
}
```

### Historial de Git {#git-history}

En CI, el plugin también sube el historial de commits del checkout cuando informa de una ejecución de tests: SHAs de commits, sus padres, fechas de commit y la rama en la que estaban la ejecución y la rama base de su pull request. No se suben contenidos de archivos, mensajes de commit ni autores. Esto es lo que indica a Tuist qué commits llegaron a tu rama por defecto, por ejemplo los que probó una cola de merges. El plugin lee el historial que ya tiene el checkout y, cuando el checkout no tiene la rama base, solicita al remoto su último commit (`git ls-remote`). No obtiene historial.

| Variable | Efecto |
| --- | --- |
| `TUIST_GIT_UPLOAD_ENABLED=false` | No lee ni sube ningún historial de Git. |
| `TUIST_GIT_UNSHALLOW_ENABLED=false` | Lee solo el checkout, sin contactar con el remoto. |
