---
{
  "title": "Selective testing",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing to run only the tests that have changed."
}
---
# Pruebas selectivas {#selective-testing}

::: advertencia REQUISITOS
<!-- -->
- Un proyecto
  <LocalizedLink href="/guides/features/projects">generado.</LocalizedLink>
- Una cuenta y un proyecto
  <LocalizedLink href="/guides/server/accounts-and-projects">Tuist.</LocalizedLink>
<!-- -->
:::

Para ejecutar pruebas de forma selectiva con tu proyecto generado, utiliza el
comando `tuist test`. El comando
<LocalizedLink href="/guides/features/projects/hashing">hash</LocalizedLink> tu
proyecto Xcode de la misma manera que lo hace para
<LocalizedLink href="/guides/features/cache#cache-warming">calentar la
caché</LocalizedLink>, y si tiene éxito, persiste los hash para determinar qué
ha cambiado en futuras ejecuciones.

En futuras ejecuciones, `tuist test` utiliza de forma transparente los hash para
filtrar las pruebas y ejecutar solo aquellas que han cambiado desde la última
ejecución exitosa.

Por ejemplo, supongamos el siguiente gráfico de dependencias:

- `FeatureA` tiene pruebas `FeatureATests` y depende de `Core`
- `FeatureB` tiene pruebas `FeatureBTests` y depende de `Core`
- `Core` tiene pruebas `CoreTests`

`La prueba tuist` se comportará de la siguiente manera:

| Acción                               | Descripción                                                           | Estado interno                                                              |
| ------------------------------------ | --------------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `Prueba tuist invocación`            | Ejecuta las pruebas en `CoreTests`, `FeatureATests` y `FeatureBTests` | Los hash de `FeatureATests`, `FeatureBTests` y `CoreTests` se mantienen.    |
| `Característica: se ha actualizado`. | El desarrollador modifica el código de un objetivo.                   | Igual que antes.                                                            |
| `Prueba tuist invocación`            | Ejecuta las pruebas en `FeatureATests` porque el hash ha cambiado.    | El nuevo hash de `FeatureATests` se mantiene.                               |
| `Se ha actualizado el núcleo`.       | El desarrollador modifica el código de un objetivo.                   | Igual que antes.                                                            |
| `Prueba tuist invocación`            | Ejecuta las pruebas en `CoreTests`, `FeatureATests` y `FeatureBTests` | El nuevo hash de `FeatureATests` `FeatureBTests` y `CoreTests` se mantiene. |

`La prueba tuist` se integra directamente con el almacenamiento en caché binario
para utilizar tantos binarios como sea posible de su almacenamiento local o
remoto y mejorar así el tiempo de compilación al ejecutar su conjunto de
pruebas. La combinación de pruebas selectivas con almacenamiento en caché
binario puede reducir drásticamente el tiempo que se tarda en ejecutar las
pruebas en su CI.

## Pruebas de interfaz de usuario {#ui-tests}

Tuist admite pruebas selectivas de pruebas de interfaz de usuario. Sin embargo,
Tuist necesita conocer el destino por adelantado. Solo si especificas el destino
`` , Tuist ejecutará las pruebas de interfaz de usuario de forma selectiva, como
por ejemplo:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
