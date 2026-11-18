---
{
  "title": "Caché de Once",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Comparte los resultados de las acciones de Once entre las máquinas de desarrollo y la CI con la caché remota de Tuist."
}
---
# Caché de Once {#once-cache}

Once puede reutilizar resultados localmente, pero la caché local de una persona desarrolladora no llega a sus compañeras de equipo ni a un nuevo trabajador de CI. Tuist ofrece una caché remota compartida para que el trabajo coincidente solo tenga que ejecutarse en una máquina.

## Configuración {#setup}

Completa <.localized_link href="/guides/get-started/once-project#connect-the-project">Get started with Once</.localized_link> y luego revisa la vinculación de la caché en el archivo `once.toml` de tu repositorio:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

Autentícate con `once auth login --provider tuist`. No se requiere ningún ejecutable de Tuist ni ningún plugin adicional de caché. El mismo proveedor admite [scripts con caché](https://buildonce.dev/docs/guide/scripted/caching) y [objetivos del grafo](https://buildonce.dev/docs/guide/graph).

Solo puede reutilizarse el trabajo declarado como cacheable por Once. Declara las entradas, salidas y el entorno del que depende el trabajo; configurar una caché remota no hace reproducible un comando arbitrario.

## Verificar la reutilización compartida {#verify-shared-reuse}

Ejecuta el mismo script con caché o objetivo del grafo en dos máquinas con entradas y configuración coincidentes:

```bash
once build MyApplication
```

La primera máquina llena la caché compartida. En una segunda máquina cuya caché local no haya visto ese resultado, un acierto y las salidas restauradas confirman la reutilización remota. Repetir el comando solo en la primera máquina puede demostrar un acierto local, no que Tuist proporcionó el resultado.

## Inspeccionar la actividad de la caché {#inspect-cache-activity}

Abre **Once Cache** en tu proyecto de Tuist para inspeccionar los aciertos de la caché de acciones, las transferencias, la latencia y el rendimiento. Abre la vista **Caché** de una ejecución para inspeccionar las decisiones de acción reportadas y la actividad de objetos de contenido.

Los resultados de acción y los objetos de contenido responden a preguntas distintas: si falta un resultado de acción, Once debe realizar el trabajo, mientras que una solicitud de objeto de contenido transfiere una entrada o salida. No consideres la descarga de un blob como una acción ejecutada ni como un acierto de la caché de acciones.

Para ver el grafo de acciones de la ejecución y los errores estructurados, consulta <.localized_link href="/guides/features/build-insights/once">Análisis de compilaciones de Once</.localized_link>.

## Integración continua {#continuous-integration}

Usa `TUIST_TOKEN` o el inicio de sesión OIDC sin interfaz de Once, como se describe en <.localized_link href="/guides/integrations/continuous-integration#once">Once en integración continua</.localized_link>. Mantén las credenciales fuera de `once.toml`.

La <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">política de subida a la caché</.localized_link> de la cuenta determina quién puede publicar resultados. Una persona desarrolladora con acceso de solo lectura puede consumir entradas generadas por CI sin convertirse en escritora de la caché.

Consulta [Integración de Once con Tuist](https://buildonce.dev/docs/guide/infrastructure/tuist#connection-recovery) para conocer los reintentos de conexión y la solución de problemas. Los reintentos no hacen que las subidas interrumpidas sean reanudables.
