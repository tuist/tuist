## Gestión de tests inestables {#managing-flaky-tests}

### Limpieza automática {#automatic-clearing}

La detección y la limpieza se gestionan mediante una **alerta de automatización** en el proyecto. Cada proyecto incluye una automatización predeterminada llamada "Detección de tests inestables" cuyo *disparador* marca un test como inestable y cuya *recuperación* elimina la marca cuando el test ha superado el periodo de recuperación configurado (por defecto, **14 días**) sin volver a activarse. Edítala en **Configuración → Automatizaciones** para cambiar el periodo de recuperación, modificar las acciones de recuperación (por ejemplo, liberar también el test de la cuarentena) o desactivar por completo la recuperación para que los tests permanezcan marcados como inestables hasta que los limpies manualmente.

### Gestión manual {#manual-management}

También puedes marcar o desmarcar manualmente los tests como inestables desde la página de detalles del caso de test. Esto resulta útil cuando:
- Quieres reconocer un test inestable conocido mientras trabajas en su corrección
- Un test se marcó incorrectamente debido a problemas de infraestructura
