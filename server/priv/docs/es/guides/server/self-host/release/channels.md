---
{
  "title": "Canales de lanzamiento",
  "titleTemplate": ":title | Autoalojamiento | Servidor | Guías | Tuist",
  "description": "Cómo Tuist distribuye las imágenes Docker del servidor y Kura a través de los canales canary, release candidate y stable, y cómo fijar tu despliegue a una línea en la que puedas confiar."
}
---

# Canales de lanzamiento {#release-channels}

El servidor de Tuist y el servidor de caché Kura se distribuyen a través de tres canales de imágenes de GHCR con distintas garantías de estabilidad. La instalación recomendada es **stable** y se actualiza una vez por semana: no avanza cada vez que una funcionalidad se fusiona en `main`, así que actualizar ya no implica absorber un lote de cambios no relacionados. Los primeros usuarios pueden seguir ejecutando compilaciones por cada commit en **canary**, y el canal **release candidate** te permite probar una línea próxima antes de que pase a estable.

Tanto el servidor como Kura siguen el mismo tren semanal y ambos se disparan al unísono con el <.localized_link href="/cli/release/channels">calendario de lanzamientos del CLI de Tuist</.localized_link>.

## Lanzamientos actuales {#live-release-status}

A continuación se muestran los lanzamientos actuales de cada componente. Consulta el <.localized_link href="/guides/server/self-host/release/calendar">calendario de lanzamientos</.localized_link> para ver las próximas ventanas y los lanzamientos recientes, incluidos parches y backports.

<.release_status status={@release_status} components="server,kura" calendar_path="/guides/server/self-host/release/calendar" locale={@locale} />

## Los canales {#the-channels}

| Canal | Formato de versión | Cadencia | ¿Actualiza `:latest`? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (p. ej., `1.351.0-canary.5`) | Cada commit en `main` | No, opt-in explícito |
| Release candidate | `X.Y.0-rc.N` (p. ej., `1.351.0-rc.1`) | Se corta desde `main` cada lunes; periodo de prueba ~1 semana | No, opt-in explícito |
| Stable | `X.Y.Z` (p. ej., `1.350.2`, `1.351.0`) | Se promociona cada lunes tras un periodo de prueba limpio | **Sí** |

Las compilaciones canary y release candidate se publican como prereleases de GitHub. Cualquier herramienta que excluya prereleases al resolver `:latest` las omitirá, por lo que solo llegarás a una de ellas si la solicitas explícitamente.

### Canary {#canary}

Cada commit en `main` publica una imagen canary. Canary siempre representa la **siguiente versión menor no publicada**: cuando se corta una línea para su lanzamiento, `main` avanza a la siguiente versión menor (por ejemplo, de `1.350.0-canary.42` a `1.351.0-canary.1`). Canary es el canal adecuado para un entorno de staging que replica producción y te da la señal más temprana posible sobre regresiones, o para verificar que una corrección que reportaste se comporta como esperabas antes de que llegue a stable.

```
ghcr.io/tuist/tuist:1.351.0-canary.5
ghcr.io/tuist/kura:0.55.0-canary.5
```

### Release candidate {#release-candidate}

Cuando una versión menor está lista para publicarse, su línea se congela en una rama protegida `releases/server-<major>.<minor>.x` (o `releases/kura-<major>.<minor>.x`) y se publica como `X.Y.0-rc.1`. La línea está congelada en funcionalidades; solo se incorporan correcciones críticas y regresiones mediante cherry-pick, y cada corrección aceptada itera la release candidate (`-rc.2`, `-rc.3`, etc.). Cuando el periodo de prueba concluye sin incidencias, la línea se promociona a stable el lunes siguiente.

```
ghcr.io/tuist/tuist:1.351.0-rc.1
ghcr.io/tuist/kura:0.55.0-rc.1
```

### Stable {#stable}

Stable es el canal recomendado y al que apunta toda la documentación. Una versión menor estable (`X.Y.0`) se publica solo cuando una release candidate ha pasado el periodo de prueba sin incidencias, y **no** avanza cuando nuevas funcionalidades se fusionan en `main`. Los parches (`X.Y.1`, `X.Y.2`, etc.) en una línea estable contienen únicamente correcciones con backport, nunca nuevas funcionalidades. `:latest` solo se mueve en una promoción a stable.

```
ghcr.io/tuist/tuist:1.351.0
ghcr.io/tuist/kura:0.55.0
ghcr.io/tuist/tuist:latest
ghcr.io/tuist/kura:latest
```

## El tren de los lunes {#the-monday-train}

Cada lunes a las 06:00 UTC, los trenes de lanzamiento de los tres componentes se disparan al unísono:

1. **06:00 UTC** — se ejecutan los trabajos de promoción. Cada uno promociona la línea release candidate más reciente que aún no sea estable (normalmente la línea cortada el lunes anterior) y no hace nada si no hay ninguna.
2. **Tras completarse cada promoción** — el trabajo de release candidate corta la siguiente línea desde `main`, de modo que una línea recién cortada nunca se promociona en la misma ejecución.

Una promoción fallida retiene el corte: solo se selecciona la línea release candidate más alta por encima de la última stable, por lo que cortar la siguiente línea sobre un fallo dejaría aislada la que no se publicó. El lunes siguiente se reintenta automáticamente la línea retenida.

## Fijar un canal {#pinning-a-channel}

Fija la etiqueta específica que desees en tu manifiesto de despliegue, valores de Helm o archivo de Docker Compose. Ejemplo con el chart de Helm:

```yaml
server:
  image:
    repository: ghcr.io/tuist/tuist
    tag: "1.350.2"          # Pinned to a stable patch
    # tag: "1.351.0-rc.1"   # Or opt into a release candidate to soak it
    # tag: "1.351.0-canary.5" # Or opt into a specific canary build

kuraRuntime:
  image:
    repository: ghcr.io/tuist/kura
    tag: "0.54.0"           # Same three channels apply to Kura
```

`:latest` en `ghcr.io/tuist/tuist` y `ghcr.io/tuist/kura` sigue la versión estable más reciente y solo se actualiza en la promoción del lunes. Fijar `:latest` te ofrece la cadencia semanal de stable sin tener que actualizar la etiqueta; fijar una versión concreta te da control total sobre cuándo actualizas.

## Estrategia recomendada {#recommended-strategy}

Los canales existen para que puedas desacoplar "obtener las correcciones más recientes" de "obtener las funcionalidades más recientes". Un valor por defecto seguro y de bajo esfuerzo es:

1. **Fija producción en una línea menor estable**, por ejemplo `ghcr.io/tuist/tuist:1.351`. Esa línea recibe únicamente correcciones con backport, nunca nuevas funcionalidades, así que las actualizaciones diarias mantienen un riesgo bajo. Actualiza la fijación cuando estés listo para adoptar la siguiente versión menor.
2. **Ejecuta un entorno de staging en canary o con una etiqueta release candidate específica.** El entorno de staging detecta las regresiones que de otro modo llegarían a tus usuarios, y cuanto más cerca esté el seguimiento de staging de `main`, antes las encontrarás. Un entorno de staging en la línea release candidate actual es un buen punto intermedio: pone a prueba los bytes exactos que se volverán stable el próximo lunes.
3. **Sigue el [changelog del servidor](/changelog) para ver lo que realmente se ha publicado.** Cada promoción a stable se anuncia allí con la lista de pull requests que se han incluido.

Si prefieres que las nuevas funcionalidades se desplieguen en producción automáticamente cuando se vuelvan estables, mantén producción en `:latest`. Ten en cuenta que la etiqueta avanza semanalmente el lunes por la mañana, así que programa tu ventana de despliegue en consecuencia.

## Backports {#backports}

Dos líneas estables del servidor (y de Kura) se mantienen activamente en todo momento: la línea actual acepta regresiones y correcciones de seguridad como pull requests de backport, y la línea anterior solo acepta correcciones críticas y de seguridad. Las líneas más antiguas no reciben backports; actualiza a una línea mantenida para recibir correcciones. Cuando una nueva línea se promociona a stable, la línea que era current pasa a ser "previous", y la línea que era "previous" deja de recibir backports.

Los backports se generan bajo demanda como lanzamientos de parche `X.Y.(Z+1)`. Nunca mueven `:latest`.
