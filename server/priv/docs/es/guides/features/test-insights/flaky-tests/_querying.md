## Consulta del estado de tests inestables y en cuarentena {#querying}

### CLI {#querying-cli}

El árbol de comandos `tuist test case` expone toda la información que Tuist rastrea sobre un caso de test:

```sh
tuist test case list --flaky                       # only flaky test cases
tuist test case list --quarantined                 # only muted or skipped test cases
tuist test case show <test_case_id>                # detail: flakiness rate, last status, run counts
tuist test case events <test_case_id>              # audit log: marked_flaky, muted, skipped, ...
tuist test case run list <test_case_id>            # run history with status and duration
tuist test case run show <test_case_run_id>        # single run, including failure breakdown
```

Todos ellos aceptan `--json` para su uso en scripts.

### API REST {#querying-rest-api}

Los mismos datos están disponibles a través de HTTP. Consulta los [endpoints de casos de test](https://tuist.dev/api/docs#tag/test-cases) en la referencia de la API para obtener la lista completa de rutas, filtros y campos de respuesta. Para cambiar el estado de un caso de test (marcar o desmarcar como inestable, silenciar, omitir), envía `PATCH /api/projects/{account_handle}/{project_handle}/tests/test-cases/{test_case_id}` con `is_flaky` o `state`. El mismo cambio está disponible como `tuist test case update` y como la herramienta MCP `update_test_case`.
