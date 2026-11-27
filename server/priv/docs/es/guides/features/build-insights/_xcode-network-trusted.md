## Informes sin credenciales en una red privada {#network-trusted-publishing}

Una implementación autoalojada puede permitir a los desarrolladores publicar informes completados sin iniciar sesión. Un operador debe configurar `TUIST_NETWORK_TRUSTED_INSIGHTS_ACCESS=true` en la instancia y reiniciarla como se describe en la <.localized_link href="/guides/server/self-host/server#network-trusted-access">guía de autoalojamiento</.localized_link>. Esto se aplica a todos los proyectos compatibles; no existe ninguna configuración en el panel de control. Configura la URL autoalojada y el proyecto en el entorno que utilice tu post-acción del esquema o terminal. La CLI descubre automáticamente la política de la instancia cuando no hay credenciales:

```sh
export TUIST_URL="https://tuist.internal.example"
tuist inspect build
# To publish local test results:
tuist inspect test
```

Cuando las credenciales están realmente ausentes, los registros de actividad y los paquetes XCResult se analizan localmente y se envían como informes estructurados. No se envía ningún archivo sin procesar, adjunto, carga de cobertura/historial, procesador remoto, referencia de fragmento ni evidencia de ejecución selectiva. Los informes siguen siendo visibles, pero no pueden actualizar el estado autenticado de los casos de prueba ni activar automatizaciones de cuarentena o fallo. El panel de control y otros comandos con privilegios siguen requiriendo inicio de sesión. Mantén la integración de caché desactivada, a menos que la instancia habilite por separado el acceso de confianza de red a la caché o se proporcionen credenciales.

Las credenciales presentes permanecen autenticadas. Las credenciales no válidas, corruptas, vacías o con actualización rechazada fallan de forma segura y permanecen en el disco, de modo que los comandos posteriores no se vuelven silenciosamente no firmados. Vuelve a iniciar sesión o cierra sesión explícitamente como acción de recuperación deliberada. Actualiza cada réplica del servidor a una versión compatible con el descubrimiento antes de actualizar los clientes sin credenciales y configura la URL final del servidor sin redirecciones. Los servidores antiguos sin descubrimiento, las instancias desactivadas y los fallos de descubrimiento siguen requiriendo autenticación. No es necesaria ninguna aceptación explícita del lado del cliente. Establece `TUIST_ACTOR_ID=""` de forma independiente para omitir la reclamación de actor configurada; la identidad verificada de la credencial no se ve afectada.
