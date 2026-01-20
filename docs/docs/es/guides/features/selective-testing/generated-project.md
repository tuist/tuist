---
{
  "title": "Generated project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with a generated project."
}
---
# Proyectos generados {#generated-projects}

::: advertencia REQUISITOS
<!-- -->
- Un proyecto generado por
  <LocalizedLink href="/guides/features/projects"></LocalizedLink>
- A <LocalizedLink href="/guides/server/accounts-and-projects">Cuenta tuista y proyecto</LocalizedLink>
<!-- -->
:::

Para ejecutar pruebas selectivamente con su proyecto generado, utilice el
comando `tuist test`. El comando
<LocalizedLink href="/guides/features/projects/hashing">hashes</LocalizedLink>
su proyecto Xcode de la misma manera que lo hace para
<LocalizedLink href="/guides/features/cache#cache-warming">calentar la caché</LocalizedLink>, y en caso de éxito, persiste los hashes en para
determinar lo que ha cambiado en futuras ejecuciones.

En futuras ejecuciones `tuist test` utiliza de forma transparente los hashes
para filtrar las pruebas y ejecutar sólo las que han cambiado desde la última
ejecución satisfactoria de la prueba.

Por ejemplo, suponiendo el siguiente gráfico de dependencias:

- `FeatureA` tiene pruebas `FeatureATests`, y depende de `Core`
- `FeatureB` tiene pruebas `FeatureBTests`, y depende de `Core`
- `Core` tiene pruebas `CoreTests`

`tuist test` se comportará como tal:

| Acción                         | Descripción                                                            | Estado interno                                                               |
| ------------------------------ | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `tuist test` invocación        | Ejecuta las pruebas en `CoreTests`, `FeatureATests`, y `FeatureBTests` | Se conservan los hashes de `FeatureATests`, `FeatureBTests` y `CoreTests`    |
| `CaracterísticaA` se actualiza | El desarrollador modifica el código de un objetivo                     | Igual que antes                                                              |
| `tuist test` invocación        | Ejecuta las pruebas en `FeatureATests` porque su hash ha cambiado      | Se mantiene el nuevo hash de `FeatureATests`                                 |
| `Se actualiza el núcleo`       | El desarrollador modifica el código de un objetivo                     | Igual que antes                                                              |
| `tuist test` invocación        | Ejecuta las pruebas en `CoreTests`, `FeatureATests`, y `FeatureBTests` | El nuevo hash de `FeatureATests` `FeatureBTests`, y `CoreTests` se persisten |

`tuist test` se integra directamente con el almacenamiento en caché de binarios
para utilizar tantos binarios de su almacenamiento local o remoto para mejorar
el tiempo de compilación al ejecutar su conjunto de pruebas. La combinación de
pruebas selectivas con el almacenamiento en caché de binarios puede reducir
drásticamente el tiempo que se tarda en ejecutar las pruebas en su CI.

## Pruebas de interfaz de usuario {#ui-tests}

Tuist admite pruebas selectivas de pruebas de interfaz de usuario. Sin embargo,
Tuist necesita conocer el destino de antemano. Sólo si especifica el parámetro
`destination`, Tuist ejecutará las pruebas de interfaz de usuario de forma
selectiva, por ejemplo:
```sh
tuist test --device 'iPhone 14 Pro'
# or
tuist test -- -destination 'name=iPhone 14 Pro'
# or
tuist test -- -destination 'id=SIMULATOR_ID'
```
