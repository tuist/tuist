---
{
  "title": "tuist.toml",
  "titleTemplate": ":title · Referencias · Tuist",
  "description": "Referencia del formato de archivo de configuración tuist.toml."
}
---

# tuist.toml {#tuist-toml}

`tuist.toml` es un archivo de configuración independiente del sistema de compilación y una evolución de `Tuist.swift`. A diferencia de `Tuist.swift`, no requiere Swift, lo que permite usarlo en cualquier plataforma y sistema de compilación. Es ideal para entornos donde Swift no está disponible, como los runners de CI basados en Linux, o cuando solo necesitas configurar ajustes relacionados con el servidor sin un manifiesto completo de `Tuist.swift`.

Tuist busca `tuist.toml` recorriendo la jerarquía de directorios hacia arriba desde el directorio de trabajo actual, deteniéndose en la primera coincidencia. Esto significa que puedes colocarlo en la raíz de tu proyecto y ejecutar comandos de Tuist desde cualquier subdirectorio.

## Claves admitidas {#supported-keys}

| Clave | Tipo | Requerido | Predeterminado | Descripción |
| --- | --- | --- | --- | --- |
| `project` | `String` | Sí | — | El identificador completo de tu proyecto (por ejemplo, `"tuist/tuist"`). |
| `url` | `String` | No | `https://tuist.dev` | La URL del servidor de Tuist. |

### Red {#network}

La tabla `[network]` configura cómo Tuist realiza conexiones HTTP salientes.

| Clave | Tipo | Requerido | Predeterminado | Descripción |
| --- | --- | --- | --- | --- |
| `proxy` | `Boolean` | No | `true` | Cuando es `true`, Tuist usa el proxy definido por `HTTPS_PROXY`/`HTTP_PROXY` si están presentes. Consulta la <.localized_link href="/guides/integrations/http-proxy">guía de proxy HTTP</.localized_link>. |
| `ca_certificate` | `String` | No | — | Ruta a un paquete de certificados CA en formato PEM o DER para confiar además del almacén raíz del sistema, por ejemplo, para un servidor autoalojado que usa una CA privada. La variable de entorno `TUIST_CA_CERTIFICATE` tiene prioridad. Consulta <.localized_link href="/cli/debugging#trusting-a-custom-ca-certificate">confiar en un certificado CA personalizado</.localized_link>. |

## Ejemplo {#example}

```toml
project = "tuist/tuist"
url = "https://tuist.dev"

[network]
proxy = true
ca_certificate = "/etc/ssl/certs/self-hosted-ca.pem"
```

## Prioridad de configuración {#configuration-precedence}

Cuando el mismo ajuste se define en varios lugares, Tuist lo resuelve usando el siguiente orden de prioridad (de mayor a menor):

1. **Opciones de CLI**
2. **Variables de entorno**
3. **Tuist.swift**
4. **tuist.toml**
5. **Valores predeterminados**
