## Informes sin credenciales en una red privada {#network-trusted-publishing}

Un despliegue autoalojado puede permitir a los desarrolladores publicar informes completados sin iniciar sesión. Un operador debe configurar `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` en la instancia y reiniciarla como se describe en la <.localized_link href="/guides/server/self-host/server#network-trusted-access">guía de autoalojamiento</.localized_link>. Esto se aplica a todos los proyectos compatibles; no existe una configuración en el panel de control. Configura la URL autoalojada y el proyecto en el entorno que usa tu esquema de posacción o terminal. La CLI descubre automáticamente la política de la instancia cuando faltan las credenciales:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

Cuando realmente faltan las credenciales, los registros de actividad y los paquetes XCResult se analizan localmente y se envían como informes estructurados. No se sube ningún archivo sin procesar, adjunto, cobertura/historial, procesador remoto, referencia de fragmento ni evidencia de ejecución selectiva. Los informes siguen siendo visibles, pero no pueden actualizar el estado autenticado de los casos de prueba ni activar automatizaciones de cuarentena o fallo. El panel de control y otros comandos con privilegios aún requieren inicio de sesión. Mantén deshabilitada la integración de caché, a menos que la instancia habilite por separado el acceso de confianza a la caché por red o se aprovisionen credenciales.

Las credenciales presentes permanecen autenticadas. Las credenciales no válidas, dañadas, vacías o con actualización rechazada fallan de forma segura y permanecen en disco, de modo que los comandos posteriores no quedan sin firmar silenciosamente. Vuelve a iniciar sesión o cierra sesión explícitamente como acción de recuperación deliberada. Actualiza cada réplica del servidor a una versión compatible con el descubrimiento antes de actualizar los clientes sin credenciales y configura la URL final del servidor sin redirecciones. Los servidores antiguos sin descubrimiento, las instancias deshabilitadas y los fallos de descubrimiento aún requieren autenticación. No es necesaria ninguna opción opt-in del lado del cliente. Establece `TUIST_ACTOR_ID=""` de forma independiente para omitir la reclamación de actor configurada; la identidad verificada de la credencial no se ve afectada.
