---
{
  "title": "Entire",
  "titleTemplate": ":title | Git forges | Integrations | Guides | Tuist",
  "description": "Publica análisis de compilación, tests, bundles y vistas previas de Tuist en Entire Trails."
}
---
# Integración con Entire {#entire}

Tuist mantiene una discusión de resumen en cada [Trail](https://docs.entire.com/guides/trails/overview) abierto o en borrador del repositorio conectado. El resumen incluye los resultados de compilación disponibles, fallos de tests y tests inestables, tamaños de bundle y vistas previas de la app, con enlaces a los informes completos en Tuist.

> [!IMPORTANT]
> **Acceso anticipado**
>
> Los plugins de Entire requieren el registro como partner, y sus discusiones de Trail y contratos de webhook son experimentales. Tu administrador de Tuist puede habilitar la integración para todas las cuentas o para cuentas seleccionadas. Tu proyecto de Entire también debe tener permiso para instalar el plugin registrado.

## Configuración {#setup}

La instalación sigue el mismo flujo que la integración con GitHub: instala el plugin para tu cuenta y luego conecta los repositorios a los proyectos de Tuist. En Tuist alojado, tu administrador se encarga del registro del plugin y de la configuración del servidor; solo necesitas seguir los pasos siguientes.

1. Abre **Ajustes → Integraciones** de tu cuenta.
2. En **Entire**, selecciona **Instalar plugin de Entire**. Elige el proyecto de Entire y los repositorios que quieres compartir con Tuist.

   ![Instala el plugin de Entire desde las integraciones de la cuenta](/images/guides/integrations/gitforge/entire/integrations.png)

3. De vuelta en Tuist, selecciona **Añadir nueva conexión de proyecto**. En **Elegir repositorio para conectar**, elige tu proyecto de Tuist y el repositorio de Entire, y luego selecciona **Crear conexión**. Si solo hay un proyecto de Tuist disponible, se selecciona automáticamente.

   ![Conecta un proyecto de Tuist a un repositorio de Entire](/images/guides/integrations/gitforge/entire/add-project-connection.png)

4. Sigue subiendo tus insights desde CI usando tus comandos de Tuist autenticados existentes. Tuist los asocia al SHA del commit actual de cada Trail; no hacen falta flags específicos de Entire en la CLI.

Un proyecto de Tuist puede mantener su conexión con GitHub mientras publica resúmenes en Entire. Esto es útil para espejos de GitHub. Los resúmenes de Trail no requieren el ejecutor de CI de Tuist ni cambian tu proveedor de CI existente.

Tuist actualiza la misma discusión a medida que llegan los insights. Al abrir o reabrir un Trail también se recuperan los insights subidos anteriormente para su commit head. Los Trails cerrados y fusionados no se actualizan. Los resultados de commits antiguos nunca se presentan como resultados del head actual. Si no existen insights para el commit actual, Tuist deja cualquier resumen existente sin cambios; cada resultado incluye su hash de commit.

Para eliminar una conexión de proyecto, abre su menú **Gestionar** y selecciona **Eliminar conexión**, igual que con GitHub. Esto detiene futuras actualizaciones y elimina los punteros locales de discusión de Tuist. Los comentarios ya publicados permanecen en Entire. Al reconectar se recupera el resumen existente cuando sigue siendo accesible. Para cambiar el acceso del plugin a los repositorios o desinstalarlo, usa la configuración de **Plugins** del proyecto en Entire.

## Configuración del servidor {#server-configuration}

Esta sección está dirigida a operadores del servidor de Tuist. Registra el plugin en Entire usando la [guía de registro de plugins](https://docs.entire.com/guides/api/plugins/register). Solicita `contents:read` y `discussions:write`. El permiso de lectura es necesario para los eventos de Trail y el descubrimiento de discusiones; no se requiere acceso de escritura al repositorio.

Configura estas variables de entorno del servidor:

| Variable | Propósito |
| --- | --- |
| `TUIST_ENTIRE_PLUGIN_SLUG` | Slug confirmado por Entire |
| `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` | Clave privada Ed25519 en formato PEM, proporcionada a través de tu almacén de secretos |
| `TUIST_ENTIRE_PLUGIN_KEY_ID` | ID de clave al usar registro de claves basado en JWKS; de lo contrario, opcional |
| `TUIST_ENTIRE_CORE_URL` | Entire Core usado para solicitudes de instalación; por defecto es `https://eu.auth.entire.io` |
| `TUIST_ENTIRE_DELIVERY_JWKS_URL` | URL de la clave de firma de webhook proporcionada por Entire en el registro |

Para despliegues gestionados con Helm, guarda la PEM privada en la bóveda de 1Password del entorno como `ENTIRE_PLUGIN/private_key`, luego habilita `server.config.entirePluginKey.enabled` junto con `server.config.managedSecrets`. External Secrets proporciona `TUIST_ENTIRE_PLUGIN_PRIVATE_KEY` a través del Secret server-config existente sin recortar la PEM multilínea. Los nombres del elemento y del campo son configurables mediante `server.config.entirePluginKey.item` y `.field`. Este mapeo está desactivado por defecto y no configura el slug ni la URL de la clave de firma del webhook; proporciónalos por separado después del registro. Cada entorno debe usar su propia clave de firma. Comparte solo la PEM pública con Entire, nunca la clave privada.

Registra `https://<your-tuist-host>/integrations/entire/callback` como la URL posterior a la instalación y `https://<your-tuist-host>/webhooks/entire` como la URL del webhook. Después de aplicar las migraciones del servidor, habilita la feature flag `entire_trails` globalmente para ofrecer la integración a todas las cuentas, o habilítala para cuentas seleccionadas. Para un lanzamiento público, pide a tu contacto en Entire que permita la instalación fuera del proyecto propietario del plugin; habilitar la feature flag de Tuist no cambia la política de instalación de Entire. Los resúmenes de Trail de Entire son independientes de la configuración de ejecución de CI de Tuist y de su feature flag.

Tuist verifica los recibos de instalación y las firmas de webhook, genera tokens de corta duración con ámbito de repositorio y descubre la región de procesamiento actual de cada repositorio antes de publicar. Los tokens nunca se incrustan en los enlaces de los informes.
