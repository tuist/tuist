### Detección entre ejecuciones {#cross-run-detection}

Incluso sin reintentos de tests, Tuist puede detectar tests inestables comparando los resultados entre distintas ejecuciones de CI con el mismo commit, esquema y destino indicado (nombre del dispositivo, plataforma y versión del sistema operativo). Si un test pasa en una ejecución de CI coincidente pero falla en otra, la ejecución fallida se marca como inestable. Esto funciona independientemente de qué resultado llegue primero.

El mismo test puede comportarse de forma consistentemente distinta según el esquema o el destino. Por ejemplo, pasar en iOS 26 y fallar en iOS 27 no indica inestabilidad. Los resultados de esquemas, dispositivos, plataformas o versiones del sistema operativo distintos no se marcan entre sí como inestables.

Las ejecuciones sin metadatos de destino, o que cubren varios destinos, solo se comparan entre sí, por lo que las diferencias de entorno entre ellas pueden seguir reportándose como inestabilidad. La detección basada en reintentos sigue aplicándose.

Esto es especialmente útil para detectar tests inestables que no fallan con suficiente consistencia como para ser capturados por los reintentos, pero aún así provocan fallos intermitentes en la CI.
