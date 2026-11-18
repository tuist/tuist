---
{
  "title": "Tests inestables en Elixir",
  "titleTemplate": ":title · Tests inestables · Análisis de tests · Funcionalidades · Guías · Tuist",
  "description": "Detecta y gestiona tests inestables en proyectos de Elixir construidos con Mix."
}
---
# Tests inestables de Elixir {#elixir-flaky-tests}

> [!IMPORTANT]
> **Requisitos**
>
> - Completa la <.localized_link href="/guides/get-started/elixir-project">configuración compartida de Elixir</.localized_link> para informar tus ejecuciones de tests

<!-- @snippet: ./_intro -->

![Tests inestables de una aplicación Phoenix](/images/guides/features/elixir/flaky-tests.png)

## Cómo funciona la detección de inestabilidad {#how-it-works}

Tuist detecta los tests inestables de dos formas:

### Reintentos de tests {#test-retries}

ExUnit ejecuta cada test una vez, por lo que un test que falla intermitentemente parece igual que uno que está roto. Con los reintentos activados, el paquete Hex vuelve a ejecutar los tests que han fallado, hasta el número de veces que hayas configurado. Un test que pasa en un reintento se informa como inestable y la ejecución tiene éxito si todos los tests fallidos acaban pasando.

Los reintentos están desactivados por defecto. Añade `test_retries` a tus opciones actuales de Tuist en `mix.exs` para activarlos:

```elixir
tuist: [project: "account/project", cache: true, test_retries: 2]
```

O para una sola ejecución, con un flag o una variable de entorno:

```bash
mix test --retries 2
TUIST_TEST_RETRIES=2 mix test
```

El flag tiene prioridad sobre la variable de entorno, y la variable de entorno sobre `mix.exs`.

Solo se vuelven a ejecutar los tests que han fallado, igual que hace `mix test --failed`, y el panel muestra cada intento de un test y cuánto ha tardado. No se reintenta una ejecución que ExUnit haya detenido antes por `--max-failures`. Tampoco se reintenta una ejecución cuyos tests fallidos hayan agotado el tiempo de espera, ya que cada reintento volvería a esperar todos los timeouts. Los reintentos también se omiten con `--warnings-as-errors`, que `mix test` ya no aplicaría, y desde la raíz de un proyecto umbrella; ejecuta los tests dentro de una de sus aplicaciones para reintentarlos.

![Un test inestable de ExUnit y su historial](/images/guides/features/elixir/flaky-test-case.png)

### Detección entre ejecuciones {#cross-run-detection}

Incluso sin reintentos de tests, Tuist puede detectar tests inestables comparando resultados entre distintas ejecuciones de CI sobre el mismo commit. Si un test pasa en una ejecución de CI pero falla en otra para el mismo commit y etiqueta de esquema (`--scheme`), la ejecución fallida se marca como inestable.

Esto es especialmente útil para detectar tests inestables que no fallan con la suficiente consistencia como para ser capturados por los reintentos, pero que aun así provocan fallos intermitentes en CI.

<!-- @snippet: ./_managing -->

## Poner en cuarentena tests inestables {#quarantining}

La cuarentena evita que un test inestable bloquee la CI mientras lo corriges. En la página del test del panel, cambia su estado a **Silenciado** o **Omitido**, o configura una automatización en **Ajustes → Automatizaciones** que silencie u omita un test cuando se vuelva inestable y lo habilite de nuevo cuando se recupere. Antes de ejecutar los tests, `mix test` lee todos los tests en cuarentena del proyecto y los aplica:

- **Silenciado**: el test se ejecuta y su fallo sigue informándose, pero una ejecución cuyos únicos fallos sean tests silenciados se considera exitosa. Los reintentos siguen volviendo a ejecutar un test silenciado que falla, por lo que uno inestable puede pasar e informarse como inestable.
- **Omitido**: el test no se ejecuta. `mix test` lista los tests omitidos antes de que empiece la ejecución.

```text
Tuist: skipping 1 quarantined test:
  MyApp.CheckoutTest: create_order/2 times out
Tuist: 1 muted test run, and their failures do not fail the run.
```

La ejecución falla como de costumbre cuando falla cualquier test que no esté silenciado, o cuando ExUnit se detiene antes por `--max-failures`.

> [!WARNING]
> **Limitaciones**
>
> - Solo las versiones recientes del paquete Hex aplican la cuarentena. Las versiones anteriores ejecutan los tests silenciados y omitidos como cualquier otro, por lo que el fallo de un test silenciado sigue haciendo fallar la ejecución. Actualiza `tuist_ex` antes de depender de esta función.
> - Los tests silenciados no se aplican con `--warnings-as-errors`, ni desde la raíz de un proyecto umbrella. Sus fallos harán fallar la ejecución. Ejecuta los tests dentro de cada aplicación del umbrella en su lugar.
> - La omisión empareja un test por su bloque describe y su nombre, no por su módulo. Un test con el mismo bloque describe y nombre en otro módulo también se omite. Consulta [cómo la omición selecciona tests](#how-skipping-selects-tests).
> - Un test omitido sigue ejecutándose cuando lo seleccionas con `--only`, `--include` o `path:line`, o cuando no está declarado con `test`, como una `property` de StreamData.
> - Si `mix test` no puede leer los tests en cuarentena, ejecuta todos los tests y cuenta todos los fallos.
> - Leer los tests en cuarentena requiere credenciales, incluso para un proyecto público. Una ejecución sin un `TUIST_TOKEN`, una sesión de `mix tuist.login` o un token de identidad de integración continua no aplica ninguna cuarentena. Esto incluye las pull requests desde forks, que normalmente se ejecutan sin secretos.
> - Con `--cover`, un test omitido cuenta como eliminado: las líneas que solo cubría ese test se informan como no cubiertas.
>
> `mix test` nombra los tests que una omisión dejó fuera por error y los tests omitidos que se ejecutaron de todos modos, después de su resumen.

### Cómo la omisión selecciona tests {#how-skipping-selects-tests}

Un test omitido se excluye con un filtro de ExUnit sobre su nombre completo, como `--exclude "test:test create_order/2 times out"`. Los filtros de ExUnit no pueden coincidir también con el módulo, así que:

- Un test con el mismo bloque describe y nombre en otro módulo también queda fuera. `mix test` nombra esos tests después de la ejecución.
- Un test que selecciones con `--only`, `--include` o `path:line` se ejecuta aunque esté omitido, porque ExUnit aplica los filtros de inclusión después de los de exclusión. Lo mismo ocurre con un test que no esté declarado con `test`, como una `property` de StreamData. `mix test` nombra esos tests después de la ejecución.

### Volver a ejecutar tests en cuarentena {#running-quarantined-tests-again}

Pasa `--no-quarantine` para ejecutar todos los tests y contar todos los fallos, por ejemplo para comprobar una corrección:

```bash
mix test --no-quarantine
```

Devuelve el test a **Habilitado** en su página para incluirlo en ejecuciones posteriores. Un test omitido no genera nuevos resultados hasta que se vuelva a ejecutar.

Si `mix test` no puede leer los tests en cuarentena, imprime una advertencia y ejecuta todos los tests sin ellos. Sin credenciales o un proyecto configurado, ejecuta todos los tests sin mostrar ninguna advertencia.

El paquete Hex aún no somete a pruebas de estrés los tests nuevos.

<!-- @snippet: ./_slack -->

## Consultar el estado de inestabilidad {#querying}

Los datos están disponibles a través de HTTP. Consulta los [endpoints de casos de test](https://tuist.dev/api/docs#tag/test-cases) en la referencia de la API para ver la lista completa de rutas, filtros y campos de respuesta. Para marcar o desmarcar un caso de test como inestable, envía `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` con `is_flaky`, o utiliza la herramienta `update_test_case` del Model Context Protocol.
