---
{
  "title": "Xcode project",
  "titleTemplate": ":title · Selective testing · Features · Guides · Tuist",
  "description": "Learn how to leverage selective testing with `xcodebuild`."
}
---
# Proyecto Xcode {#xcode-project}

::: advertencia REQUISITOS
<!-- -->
- A <LocalizedLink href="/guides/server/accounts-and-projects">Cuenta tuista y proyecto</LocalizedLink>
<!-- -->
:::

Puede ejecutar las pruebas de sus proyectos Xcode de forma selectiva a través de
la línea de comandos. Para ello, puede anteponer al comando `xcodebuild` `
tuist` - por ejemplo, `tuist xcodebuild test -scheme App`. El comando realiza un
hash del proyecto y, si tiene éxito, persiste el hash para determinar qué ha
cambiado en futuras ejecuciones.

En futuras ejecuciones `tuist xcodebuild test` utiliza de forma transparente los
hashes para filtrar las pruebas y ejecutar sólo las que han cambiado desde la
última ejecución satisfactoria de la prueba.

Por ejemplo, suponiendo el siguiente gráfico de dependencias:

- `FeatureA` tiene pruebas `FeatureATests`, y depende de `Core`
- `FeatureB` tiene pruebas `FeatureBTests`, y depende de `Core`
- `Core` tiene pruebas `CoreTests`

`tuist xcodebuild test` se comportará como tal:

| Acción                             | Descripción                                                            | Estado interno                                                               |
| ---------------------------------- | ---------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `tuist xcodebuild test` invocación | Ejecuta las pruebas en `CoreTests`, `FeatureATests`, y `FeatureBTests` | Se conservan los hashes de `FeatureATests`, `FeatureBTests` y `CoreTests`    |
| `CaracterísticaA` se actualiza     | El desarrollador modifica el código de un objetivo                     | Igual que antes                                                              |
| `tuist xcodebuild test` invocación | Ejecuta las pruebas en `FeatureATests` porque su hash ha cambiado      | Se mantiene el nuevo hash de `FeatureATests`                                 |
| `Se actualiza el núcleo`           | El desarrollador modifica el código de un objetivo                     | Igual que antes                                                              |
| `tuist xcodebuild test` invocación | Ejecuta las pruebas en `CoreTests`, `FeatureATests`, y `FeatureBTests` | El nuevo hash de `FeatureATests` `FeatureBTests`, y `CoreTests` se persisten |

Para utilizar `tuist xcodebuild test` en su CI, siga las instrucciones de la
<LocalizedLink href="/guides/integrations/continuous-integration">Guía de integración continua</LocalizedLink>.

Eche un vistazo al siguiente vídeo para ver las pruebas selectivas en acción:

<iframe title="Run tests selectively in your Xcode projects" width="560" height="315" src="https://videos.tuist.dev/videos/embed/1SjekbWSYJ2HAaVjchwjfQ" frameborder="0" allowfullscreen="" sandbox="allow-same-origin allow-scripts allow-popups allow-forms"></iframe>
