---
{
  "title": "Canales de lanzamiento",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Cómo Tuist distribuye la CLI a través de los canales canary, release candidate y stable, y cómo fijar tu equipo a una línea en la que puedas confiar."
}
---

# Canales de lanzamiento {#release-channels}

El CLI de Tuist se distribuye a través de tres canales con diferentes garantías de estabilidad. La instalación recomendada es **stable** y avanza lentamente: no progresa cada vez que se integra una funcionalidad, por lo que actualizar ya no significa absorber un lote de cambios no relacionados. Los usuarios pioneros pueden seguir ejecutando compilaciones por cada commit en **canary**, y el canal **release candidate** permite a los equipos probar una línea próxima antes de que se vuelva estable.

## Lanzamientos actuales {#live-release-status}

La promoción a stable está programada para los lunes a las 06:00 UTC. Después de una promoción programada exitosa, la siguiente release candidate se corta desde `main`, y las canaries subsiguientes pasan a la siguiente versión menor. Consulta el <.localized_link href="/cli/release/calendar">calendario de lanzamientos</.localized_link> para ver las próximas ventanas y los lanzamientos recientes, incluidos parches y backports.

<.release_status status={@release_status} components="cli" calendar_path="/cli/release/calendar" locale={@locale} />

## Los canales {#the-channels}

| Canal | Formato de versión | Frecuencia | ¿Resuelto por defecto? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (p. ej., `4.201.0-canary.42`) | Cada commit en `main` | No — requiere opt-in explícito |
| Release candidate | `X.Y.0-rc.N` (p. ej., `4.200.0-rc.1`) | Cortado desde `main` cada lunes, prueba ~1 semana | No — requiere opt-in explícito |
| Stable | `X.Y.Z` (p. ej., `4.200.0`, `4.200.1`) | Promovido cada lunes después de una prueba limpia | **Sí** |

Las compilaciones Canary y Release Candidate se publican como prereleases. Herramientas como Mise y Homebrew excluyen las prereleases al resolver `latest`, una instalación básica o un pin de línea, por lo que solo llegarás a una de ellas si la solicitas explícitamente.

### Canary {#canary}

Cada commit en `main` publica una canary. Canary siempre representa la **siguiente versión menor no lanzada**: una vez que se corta una línea para su lanzamiento, `main` avanza a la siguiente versión menor (por ejemplo, de `4.200.0-canary.42` a `4.201.0-canary.1`). Canary es el canal adecuado para los usuarios pioneros que quieren la señal más temprana posible, o para verificar que una corrección que reportaste o contribuiste se comporta como se espera antes de llegar a stable.

### Release candidate {#release-candidate}

Cuando una versión menor está lista para publicarse, su línea se congela en una rama protegida `releases/<major>.<minor>.x` y se publica como `X.Y.0-rc.1`. La línea tiene las funcionalidades congeladas; solo se incorporan correcciones críticas y regresiones, y cada corrección aceptada incrementa la RC (`-rc.2`, `-rc.3`, …). Después de que el periodo de prueba concluye limpiamente, la línea se promueve a stable.

### Stable {#stable}

Stable es el canal recomendado y al que apunta toda la documentación. Una versión menor stable (`X.Y.0`) se publica solo cuando una release candidate ha pasado la prueba limpiamente, y **no** avanza cuando nuevas funcionalidades se integran en `main`. Los parches (`X.Y.1`, `X.Y.2`, …) en una línea stable contienen solo correcciones con backport, nunca nuevas funcionalidades.

## Elegir una versión {#choosing-a-version}

Con <.localized_link href="/guides/install-tuist">Mise</.localized_link> (recomendado):

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Con Homebrew, `brew install --formula tuist` siempre instala la última stable; las prereleases no se distribuyen a través de la fórmula.

## Estrategia recomendada {#recommended-strategy}

1. **Fija una línea stable**, por ejemplo `tuist@4.200`. Esa línea recibe solo correcciones con backport, nunca nuevas funcionalidades, por lo que las actualizaciones diarias mantienen un riesgo bajo.
2. **Adopta nuevas funcionalidades deliberadamente.** Cuando estés listo para la siguiente versión menor, pruébala en el canal release candidate y luego mueve tu pin a la nueva línea stable.
3. **Prueba canary** en un entorno no crítico si eres un usuario pionero que quiere la señal más temprana posible.

## Soporte y backports {#support-and-backports}

Dos líneas stable se mantienen activamente en todo momento:

| Línea | Recibe |
| --- | --- |
| Actual (`X.Y.x`) | Regresiones y correcciones de seguridad |
| Anterior (`X.(Y-1).x`) | Solo correcciones críticas y de seguridad |
| Antiguas | Ninguna — actualiza a una línea mantenida |

Las correcciones llegan primero a `main` (canary). Las regresiones y las correcciones de seguridad se backportean a la línea stable actual, y la línea anterior recibe solo correcciones críticas y de seguridad. Otras correcciones de errores no se backportean; se publican con la siguiente versión menor. Cuando una nueva línea se promueve a stable, la línea que era "actual" pasa a ser "anterior", y la línea que era "anterior" deja de recibir backports.

Independientemente del canal, el servidor de Tuist se mantiene <.localized_link href="/cli/compatibility">compatible</.localized_link> con cualquier CLI lanzado en los últimos 3 meses, por lo que fijar una línea stable nunca te sitúa fuera de la ventana de soporte siempre que actualices dentro de ese periodo.
