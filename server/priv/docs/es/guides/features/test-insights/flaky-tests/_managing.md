## Gestión de tests inestables {#managing-flaky-tests}

### Limpieza automática {#automatic-clearing}

La detección y la limpieza se ejecutan mediante una **alerta de automatización** en el proyecto. Cada proyecto tiene una automatización predeterminada llamada "Detección de tests inestables" cuyo *disparador* marca un test como inestable y cuya *recuperación* elimina la marca una vez que el test ha transcurrido el periodo de recuperación configurado (por defecto **14 días**) sin volver a dispararse. Edítala en **Configuración → Automatizaciones** para cambiar el periodo de recuperación, modificar las acciones de recuperación (por ejemplo, liberar también el test de la cuarentena) o desactivar la recuperación por completo, de modo que los tests permanezcan marcados como inestables hasta que los limpies manualmente.

### Gestión manual {#manual-management}

También puedes marcar o desmarcar manualmente los tests como inestables desde la página de detalles del caso de test. Esto es útil cuando:
- Quieres reconocer un test inestable conocido mientras trabajas en una solución
- Un test se marcó incorrectamente debido a problemas de infraestructura
