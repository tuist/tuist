---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Publica información sobre compilaciones, tests, bundles y previews de Tuist en Entire Trails."
}
---
# Integración con Entire {#entire}

Tuist puede publicar análisis de compilaciones, tests, previsualizaciones y paquetes en [Trails](https://docs.entire.com/guides/trails/overview) abiertos y en borrador de los repositorios de [Entire](https://entire.com). Cada Trail recibe una puerta de Tuist con el informe de ejecución, hallazgos de cambio completo para tests fallidos e inestables, y un comentario resumen que Tuist actualiza a medida que llegan nuevos análisis, en lugar de publicar uno nuevo por cada subida.

Instalar el plugin no ejecuta compilaciones ni tests. Tus flujos de trabajo existentes siguen subiendo resultados a Tuist, y la integración incorpora esos resultados a tus Trails.

## Configuración {#setup}

Un administrador de la cuenta de Tuist instala el plugin y luego conecta los repositorios a los proyectos de Tuist, como ocurre con las integraciones de <.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link> y <.localized_link href="/guides/integrations/gitforge/origin">Origin</.localized_link>.

1. Abre \*\***Settings → Integrations**\*\* de tu cuenta.
2. En la tarjeta de Entire, elige \*\***Install Entire plugin**\*\*. Selecciona el proyecto y los repositorios de Entire que quieres compartir con Tuist.

   ![Instala el plugin de Entire desde las integraciones de la cuenta](/images/guides/integrations/gitforge/entire/integrations.png)

3. De vuelta en Tuist, elige \*\***Add new project connection**\*\*. En \*\***Choose repository to connect to**\*\*, selecciona tu proyecto de Tuist y el repositorio de Entire, y luego elige \*\***Create Connection**\*\*. Si solo hay un proyecto de Tuist disponible, se selecciona automáticamente.

   ![Conecta un proyecto de Tuist a un repositorio de Entire](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Sigue subiendo los resultados desde CI con tus comandos de Tuist ya autenticados, por ejemplo usando un <.localized_link href="/guides/server/authentication#account-tokens">token de cuenta</.localized_link>. Tuist asocia los resultados al commit HEAD actual de cada Trail, por lo que no hacen falta flags específicos de Entire.

Un proyecto de Tuist puede mantener su conexión con GitHub y también publicar en Entire, lo cual es útil cuando el repositorio de Entire replica un repositorio de GitHub. La integración no requiere el ejecutor de CI de Tuist ni cambia tu proveedor de CI.

## Informes y permisos {#reports-and-permissions}

Al instalar el plugin, otorgas los permisos necesarios para encontrar Trails y publicar informes:

| Permiso | Uso |
| --- | --- |
| Contenido del repositorio: lectura | Recibir eventos de Trail y encontrar Trails abiertos y en borrador con sus commits HEAD. |
| Checks: escritura | Publicar la puerta de Tuist en el commit HEAD del Trail. |
| Hallazgos: escritura | Publicar tests fallidos e inestables como hallazgos y resolver los hallazgos que sustituye un informe más reciente. |
| Discusiones: escritura | Publicar y actualizar el comentario resumen. Sin este permiso, Tuist sigue publicando la puerta y los hallazgos. |

Tuist no necesita acceso de escritura a tu código fuente ni permiso para fusionar Trails.

Tuist publica tres elementos en cada Trail:

- **Puerta:** la comprobación de Tuist aparece bajo \*\***Gates**\*\* con el informe de ejecución y un enlace al proyecto en Tuist. Aparece listada bajo el plugin de Tuist, por separado de la puerta de \*\***Checks**\*\* de un espejo de GitHub. Finaliza con una conclusión `neutral`, que Entire muestra como aprobada, porque los resultados subidos no indican a Tuist si todos los trabajos de CI esperados han terminado. No bloquea la fusión, incluso cuando hay hallazgos, así que mantén las comprobaciones requeridas de tu proveedor de CI para aplicar el criterio de aprobado/reprobado.
- **Hallazgos:** los tests fallidos e inestables aparecen como hallazgos de cambio completo que enlazan a los casos de test en Tuist. Los hallazgos no contribuyen a la puerta de revisión del Agente de Entire.
- **Comentario resumen:** al igual que el comentario de pull request en GitHub y Origin, cada proyecto mantiene un único comentario de Informe de Ejecución de Tuist por Trail. Si lo eliminas, el siguiente informe lo vuelve a publicar.

A medida que llegan nuevos resultados, Tuist publica un informe actualizado para el commit HEAD actual del Trail y resuelve los hallazgos que sustituye. Los reintentos no crean revisiones, hallazgos ni comentarios duplicados, incluso cuando se pierde la respuesta de Entire a una publicación. Al abrir o volver a abrir un Trail, se recuperan los resultados ya subidos para su commit HEAD. Si no existen resultados para el commit HEAD actual, Tuist no publica nada nuevo, por lo que la puerta de un commit anterior no puede cumplir los requisitos para el nuevo HEAD. Los Trails cerrados y fusionados no se actualizan.

La tarjeta de Entire enumera las conexiones entre proyectos y repositorios. Elige \*\***Manage → Remove connection**\*\* en una conexión de proyecto para detener sus informes sin desinstalar el plugin. Los informes ya publicados permanecen en Entire y, al reconectar, se generan nuevos informes. Para cambiar el acceso del plugin a los repositorios o desinstalarlo, usa la configuración de \*\***Plugins**\*\* del proyecto en Entire.

## Servidores autoalojados {#server-configuration}

Si alojas tu propio servidor de Tuist, registra y configura primero un plugin de Entire para tu despliegue. Sigue las <.localized_link href="/guides/server/self-host/server#platform-entire">instrucciones de autoalojamiento de Entire</.localized_link> y luego vuelve a los pasos de configuración anteriores para conectar cuentas y proyectos.
