---
{
  "title": "Caché de Struo",
  "titleTemplate": ":title · Caché · Funcionalidades · Guías · Tuist",
  "description": "Comparte los resultados de las acciones de Struo entre las máquinas de los desarrolladores y la CI con la caché remota de Tuist."
}
---
# Caché de Struo {#struo-cache}

<a id="once-cache"></a>

Struo puede reutilizar resultados localmente, pero la caché local de un desarrollador no llega a sus compañeros de equipo ni a un nuevo agente de CI. Tuist proporciona una caché remota compartida para que el trabajo coincidente solo necesite ejecutarse en una máquina.

## Configuración {#setup}

Completa <.localized_link href="/guides/get-started/struo-project#connect-the-project">Primeros pasos con Struo</.localized_link> y luego verifica la vinculación de la caché en el archivo `struo.toml` de tu repositorio:

```toml
[infrastructures.tuist]
kind = "tuist"
account = "acme"
project = "app"

[infrastructure.cache]
provider = "tuist"
```

Autentícate con `struo auth login --provider tuist`. No se requiere ningún ejecutable de Tuist ni ningún plugin adicional de caché. El mismo proveedor admite [scripts almacenables en caché](https://struo.run/docs/guide/scripted/caching) y [targets de grafo](https://struo.run/docs/guide/graph).

Solo se puede reutilizar el trabajo declarado como almacenable en caché por Struo. Declara las entradas, salidas y el entorno del que depende el trabajo; configurar una caché remota no hace reproducible un comando arbitrario.

## Verificar la reutilización compartida {#verify-shared-reuse}

Ejecuta el mismo script almacenable en caché o target de grafo en dos máquinas con entradas y configuración coincidentes:

```bash
struo build MyApplication
```

La primera máquina completa la caché compartida. En una segunda máquina cuya caché local no ha visto ese resultado, un acierto y las salidas restauradas confirman la reutilización remota. Repetir el comando únicamente en la primera máquina puede demostrar un acierto local, no que Tuist haya proporcionado el resultado.

## Inspeccionar la actividad de la caché {#inspect-cache-activity}

Abre **Struo Cache** en tu proyecto de Tuist para inspeccionar los aciertos de la caché de acciones, las transferencias, la latencia y el rendimiento. Abre la vista **Caché** de una ejecución para inspeccionar las decisiones de acción reportadas y la actividad de objetos de contenido.

Los resultados de acción y los objetos de contenido responden a preguntas distintas: la falta de un resultado de acción significa que Struo debe realizar el trabajo, mientras que una solicitud de objeto de contenido transfiere una entrada o salida. No consideres la descarga de un blob como una acción ejecutada o como un acierto de la caché de acciones.

Para ver el grafo de acciones de la ejecución y los errores estructurados, consulta <.localized_link href="/guides/features/build-insights/struo">Análisis de compilaciones de Struo</.localized_link>.

## Integración continua {#continuous-integration}

Usa `TUIST_TOKEN` o el inicio de sesión OIDC sin interfaz de Struo, como se describe en <.localized_link href="/guides/integrations/continuous-integration#struo">Struo en integración continua</.localized_link>. Mantén las credenciales fuera de `struo.toml`.

La <.localized_link href="/guides/features/cache#restrict-uploads-to-ci">política de subida a la caché</.localized_link> de la cuenta determina quién puede publicar resultados. Un desarrollador con acceso de solo lectura puede consumir entradas generadas por CI sin convertirse en escritor de la caché.

Consulta [Integración de Struo con Tuist](https://struo.run/docs/guide/infrastructure/tuist#connection-recovery) para ver el reintento de conexiones y la solución de problemas. Los reintentos no hacen que las subidas interrumpidas sean reanudables.
