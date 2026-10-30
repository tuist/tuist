---
{
  "title": "Cobertura de código en Elixir",
  "titleTemplate": ":title · Cobertura de código · Funcionalidades · Guías · Tuist",
  "description": "Sube la cobertura de líneas de tu proyecto Elixir con mix test --cover y hazle seguimiento por archivo, por aplicación y por commit."
}
---
# Cobertura de código en Elixir {#elixir-code-coverage}

La cobertura de código te indica qué líneas de tu código ejecutaron tus tests. El paquete Hex sube la cobertura de líneas de cada ejecución de `mix test --cover`, y Tuist consolida las ejecuciones de un commit en una única cifra, para el proyecto, cada aplicación OTP y cada archivo. La página **Cobertura de código** del panel la muestra por commit y como tendencia para cada rama.

> [!IMPORTANT] REQUIREMENTS
> - Completa la <.localized_link href="/guides/get-started/elixir-project">configuración compartida de Elixir</.localized_link>, que enruta `mix test` a través del paquete

## Configuración {#setup}

### Ejecuta tus tests con cobertura {#run-your-tests}

Pasa `--cover`, como harías con `mix test` sin Tuist:

```sh
mix test --cover
```

El paquete sube la cobertura junto con los resultados de los tests de la ejecución. Cuando la suite finaliza, también hace lo que hace la herramienta de cobertura de Mix, configurada con las mismas opciones de `test_coverage`:

- **Resumen.** Imprime la cobertura de cada módulo y el total. `summary: false` la desactiva.
- **Umbral.** Falla la ejecución con el estado de salida 3 cuando el total cae por debajo del umbral, que es del 90 % a menos que establezcas otro:

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

Al igual que en Mix, el umbral pertenece al resumen, por lo que `summary: false` desactiva ambos. Para imprimir el resumen sin fallar la ejecución, establece `threshold: 0`. Los módulos listados en `test_coverage: [ignore_modules: [...]]` se excluyen del resumen y de la subida.

Tuist rastrea la cobertura por commit, por lo que necesita que tu proyecto esté en un repositorio Git: una ejecución fuera de uno sube sus resultados de test pero no la cobertura.

La cobertura depende del <.localized_link href="/guides/features/test-insights/elixir#git-history">historial de Git</.localized_link> que sube el paquete, lo que sitúa el commit en su rama. Las ejecuciones en integración continua siempre lo suben, y las ejecuciones con `--cover` lo suben en cualquier máquina. Con `--cover`, el paquete también encuentra dónde se bifurcó una pull request: obtiene la rama base y profundiza un clon superficial tanto como sea necesario. Establece `TUIST_GIT_UNSHALLOW_ENABLED=false` para evitar que contacte con el remoto.

### Ejecuciones fragmentadas {#sharded-runs}

Cuando <.localized_link href="/guides/features/test-sharding/elixir">fragmentas tus tests</.localized_link>, ejecuta cada fragmento con `--cover`:

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

En un runner nuevo, usa el comando de bootstrap de la <.localized_link href="/guides/features/test-sharding/elixir#test-phase">fase de test</.localized_link> de la guía de fragmentación, que evita que Mix compile todas las dependencias antes de que el fragmento descargue su build, y añádele `--cover`.

Un fragmento informa solo de su propia cobertura y no comprueba el umbral, ya que ejecuta parte de la suite. Tuist fusiona los fragmentos de una ejecución en una única cifra.

Cada fragmento añade los contadores de cobertura al build que descarga. Para hacerlo una sola vez, pasa `--cover` también a la fase de build:

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

Déjalo desactivado cuando mantengas el directorio de build entre ejecuciones de pipeline y lo reutilices en ejecuciones que no recopilan cobertura, para que ese build permanezca sin contadores.

### Completa cada commit en CI {#complete-each-commit}

La cobertura de un commit suele provenir de varios jobs: uno por fragmento, por versión de base de datos o por aplicación. Tuist no puede saber cuándo ha informado el último de ellos, así que debes indicárselo. Una vez que haya terminado cada job de test para un commit, ejecuta esto en un job que dependa de todos ellos:

```sh
MIX_ENV=test mix tuist.coverage.complete
```

La tarea lee el commit desde `GIT_COMMIT` o desde el `HEAD` del checkout; pasa `--commit <sha>` para indicar otro. Hasta que un commit esté completo, su cobertura aparece como **En progreso** y queda fuera de la tendencia de su rama.

## Cómo funciona {#how-it-works}

### Contadores de líneas nativos {#native-line-counters}

La herramienta de cobertura de Mix vuelve a compilar cada módulo para `cover` de Erlang al inicio de cada ejecución, lo que resulta lento en proyectos grandes. El paquete cuenta en su lugar con los contadores de líneas nativos del runtime. Solo recompila los módulos que una compilación escribió desde la última ejecución, cambia el runtime a esos contadores y los lee cuando finaliza la suite. Se omite la herramienta de cobertura de Mix, pero se mantienen su resumen y su umbral.

El paquete recurre a la herramienta de cobertura de Mix, con la misma subida, para:

- La raíz de un proyecto umbrella. Ejecuta los tests dentro de cada aplicación para contar de forma nativa.
- Un proyecto que establece su propio `test_coverage: [tool: ...]`.
- Un runtime sin JIT, que no puede contar de forma nativa.

### Qué mide Tuist {#what-tuist-measures}

- **Aplicaciones.** Cada aplicación OTP es un objetivo en el panel, con su propia cobertura.
- **Solo código de producto.** Los archivos bajo tus rutas de test son código de test. Tuist los almacena pero los excluye de todas las cifras.
- **Líneas por archivo.** Una línea cuenta una vez por archivo, independientemente de a cuántos módulos pertenezca.
- **Funciones.** Cada línea pertenece a la función cuya cláusula comienza más cerca por encima de ella. Las funciones que genera el compilador o una macro, como `__info__/1` o `__schema__/1`, no se listan, pero sus líneas siguen contando para su archivo.

Por ello, las cifras de Tuist difieren del informe de cobertura propio de Mix en algunos aspectos: excluyen el código de test y cuentan líneas por archivo en lugar de por módulo. El conteo nativo también ve el código que se ejecuta mientras tu aplicación inicia, y excluye las líneas que el compilador demuestra que nunca pueden ejecutarse, que la herramienta de Mix reporta como nunca cubiertas.

### Tests omitidos {#skipped-tests}

Tuist no puede arrastrar la cobertura de los tests que una ejecución omite: el paquete registra lo que ejecutó toda la ejecución, no lo que ejecutó cada test. Así, cuando los propios argumentos de una ejecución omiten tests, con `--only`, `--exclude`, `--failed`, `--stale`, `--name-pattern`, `--max-failures`, o archivos o líneas de test, la cobertura del commit es **Incompleta**, a menos que también se haya ejecutado una ejecución de la misma variante que no omitiera nada. Dos ejecuciones que cada una omiten tests, como `--exclude slow` y `--only slow`, siguen haciendo que el commit sea incompleto, aunque juntas hayan ejecutado todos los tests.

Algunos tests se omiten a propósito y no hacen que un commit sea incompleto:

- **Exclusiones de tu helper de test.** Los tests que `ExUnit.start(exclude: [...])` omite por defecto son la elección de tu proyecto sobre qué ejecuta su suite por defecto, por lo que Tuist no los cuenta como faltantes. Ejecútalos en otro job, con `--include` o `--only`, para añadir su cobertura al commit.
- **Tests omitidos en el código** con `@tag :skip`.
- **Tests que omite la <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">cuarentena</.localized_link>.** Se omiten como si hubieran sido eliminados, por lo que las líneas que solo ellos cubrieron cuentan como no cubiertas.

### Commits completos e incompletos {#commit-status}

Cada commit en el dashboard tiene un estado:

| Estado | Significado |
| --- | --- |
| En progreso | Las ejecuciones han reportado cobertura, pero `mix tuist.coverage.complete` aún no se ha ejecutado para el commit. |
| Completo | Se ejecutaron todos los tests de las ejecuciones del commit, o se omitieron a propósito. |
| Incompleto | No se pudo determinar parte de la cobertura, por lo que la cifra es un límite inferior. |
| No medido | Ninguna ejecución reportó cobertura para el commit. |

La tendencia de una rama solo incluye commits completos. Un commit es incompleto cuando, por ejemplo:

- Cada ejecución de una variante omitió tests con sus propios argumentos.
- A cada ejecución de una variante le faltaban algunos de sus shards.
- La cobertura de una variante provenía únicamente de ejecuciones de CI en un checkout con cambios sin confirmar.

Una variante es la etiqueta que pasas con `--scheme`, como una versión de base de datos. Las ejecuciones sin etiqueta constituyen una variante. La cifra del commit fusiona todas las ejecuciones, pero Tuist verifica la completitud de cada variante por separado, por lo que cada variante necesita una ejecución que no omita nada.

## Impacto en el rendimiento {#performance-impact}

Recopilar cobertura añade sobrecarga, por lo que las ejecuciones con `--cover` tardan más que las ejecuciones sin ella. La primera ejecución recompila tus módulos con los contadores de líneas; las ejecuciones posteriores solo recompilan lo que cambió, por lo que su coste es mucho menor. En proyectos grandes, el conteo nativo también es mucho más rápido que la herramienta de cobertura de Mix.

## Limitaciones {#limitations}

- **Sin informe HTML.** El conteo nativo no escribe ningún informe en el directorio `test_coverage: [output: ...]`, y la ejecución emite una advertencia cuando está configurado. Las páginas de archivos del dashboard muestran las líneas cubiertas en su lugar.
- **Los reintentos no añaden cobertura.** Con los <.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">reintentos de test</.localized_link>, la cobertura corresponde al primer intento. Ese intento ya ejecutó los tests fallidos, por lo que las únicas líneas faltantes son aquellas a las que llega un test inestable en un reintento pero no en su primer intento.
- **Sin cobertura desde pull requests de forks.** La cobertura solo la suben las ejecuciones que se autentican con Tuist, y la CI suele retener los secretos y tokens de identidad de las pull requests abiertas desde forks, por lo que esas ejecuciones no reportan cobertura. Una vez fusionado, el commit se ejecuta en tu rama con credenciales y reporta su cobertura como de costumbre.

## Consulta de cobertura {#querying}

La página **Cobertura de código** del dashboard muestra la cifra de cada commit, sus aplicaciones y sus archivos, con las líneas que cubrió cada ejecución. Los mismos datos están disponibles para los agentes a través del <.localized_link href="/guides/features/agentic-coding/mcp">servidor de Model Context Protocol</.localized_link>.
