### Habilitarlo {#enabling-stress-testing}

La protección está desactivada de forma predeterminada. Establece un modo:

- **`report`**: advierte sobre cada caso de test inestable. La ejecución finaliza según su propio resultado.
- **`enforce`**: un caso de test inestable hace fallar la ejecución, con el mismo código de salida que un test fallido.

Comienza con `report` durante un par de semanas para ver qué habría bloqueado `enforce`.
