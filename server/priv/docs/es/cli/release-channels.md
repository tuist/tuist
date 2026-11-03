---
{
  "title": "Canales de lanzamiento",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Cómo Tuist distribuye la CLI a través de los canales canary, release candidate y stable, y cómo fijar tu equipo a una línea en la que puedas confiar."
}
---

# Canales de lanzamiento {#release-channels}

El CLI de Tuist se distribuye a través de tres canales con diferentes garantías de estabilidad. La instalación recomendada es **stable** y avanza lentamente: no progresa cada vez que se integra una funcionalidad, por lo que actualizar ya no implica absorber un lote de cambios no relacionados. Los primeros adoptantes aún pueden ejecutar compilaciones por cada commit en **canary**, y el canal **release candidate** permite a los equipos probar una línea próxima antes de que se vuelva estable.

## Los canales {#the-channels}

| Canal | Formato de versión | Frecuencia | ¿Se resuelve por defecto? |
| --- | --- | --- | --- |
| Canary | `X.Y.0-canary.N` (p. ej., `4.201.0-canary.42`) | Cada commit en `main` | No — requiere activación explícita |
| Release candidate | `X.Y.0-rc.N` (p. ej., `4.200.0-rc.1`) | Generado desde `main` cada lunes, periodo de prueba de ~1 semana | No — requiere activación explícita |
| Stable | `X.Y.Z` (p. ej., `4.200.0`, `4.200.1`) | Promovido cada lunes tras un periodo de prueba limpio | **Sí** |

Las compilaciones de Canary y Release Candidate se publican como prereleases. Herramientas como Mise y Homebrew excluyen las prereleases al resolver `latest`, una instalación básica o una fijación de línea, por lo que solo llegarás a una de ellas si la solicitas explícitamente.

### Canary {#canary}

Cada commit en `main` publica una versión canary. Canary siempre representa la **siguiente versión menor no publicada**: una vez que se corta una línea para su lanzamiento, `main` avanza a la siguiente versión menor (por ejemplo, de `4.200.0-canary.42` a `4.201.0-canary.1`). Canary es el canal adecuado para los primeros adoptantes que quieren la señal más temprana posible, o para verificar que una corrección que has reportado o contribuido se comporta como se espera antes de llegar a stable.

### Release candidate {#release-candidate}

Cuando una versión menor está lista para publicarse, su línea se congela en una rama protegida `releases/<major>.<minor>.x` y se publica como `X.Y.0-rc.1`. La línea está congelada en cuanto a funcionalidades; solo se incorporan correcciones críticas y regresiones, y cada corrección aceptada incrementa la RC (`-rc.2`, `-rc.3`, …). Tras concluir limpiamente el periodo de prueba, la línea se promueve a stable.

### Stable {#stable}

Stable es el canal recomendado y al que apunta toda la documentación. Una versión menor estable (`X.Y.0`) se publica solo cuando una release candidate ha pasado limpiamente el periodo de prueba, y **no** avanza cuando se integran nuevas funcionalidades en `main`. Los parches (`X.Y.1`, `X.Y.2`, …) en una línea estable contienen únicamente correcciones retroportadas, nunca nuevas funcionalidades.

## Elegir una versión {#choosing-a-version}

Con [Mise](/en/guides/install-tuist) (recomendado):

```bash
mise use tuist@latest              # Latest stable (recommended)
mise use tuist@4.200               # Pin to a stable line; receives backported fixes only
mise use tuist@4.200.1             # Pin to an exact stable patch
mise use tuist@4.201.0-rc.1        # Opt into a release candidate to soak it
mise use tuist@4.201.0-canary.42   # Opt into a specific canary build
```

Con Homebrew, `brew install --formula tuist` siempre instala la última versión stable; las prereleases no se distribuyen a través de la fórmula.

## Estrategia recomendada {#recommended-strategy}

1. **Fija una línea stable**, por ejemplo `tuist@4.200`. Esa línea recibe únicamente correcciones retroportadas, nunca nuevas funcionalidades, por lo que las actualizaciones diarias mantienen un riesgo bajo.
2. **Adopta nuevas funcionalidades de forma deliberada.** Cuando estés listo para la siguiente versión menor, pruébala en el canal release candidate y luego mueve tu fijación a la nueva línea stable.
3. **Prueba canary** en un entorno no crítico si eres un primer adoptante que quiere la señal más temprana posible.

## Soporte y retroportaciones {#support-and-backports}

En todo momento se mantienen activamente dos líneas stable:

| Línea | Recibe |
| --- | --- |
| Actual (`X.Y.x`) | Regresiones y correcciones de seguridad |
| Anterior (`X.(Y-1).x`) | Solo correcciones críticas y de seguridad |
| Anteriores | Ninguna: actualiza a una línea mantenida |

Las correcciones llegan primero a `main` (canary). Las regresiones y las correcciones de seguridad se retroportan a la línea stable actual, y la línea anterior recibe solo correcciones críticas y de seguridad. Otras correcciones de errores no se retroportan; se publican con la siguiente versión menor. Cuando una nueva línea se promueve a stable, la que era actual pasa a ser "anterior", y la que era "anterior" deja de recibir retroportaciones.

Independientemente del canal, el servidor de Tuist se mantiene [compatible](/en/cli/compatibility) con cualquier CLI lanzado en los últimos 3 meses, por lo que fijar una línea stable nunca te sitúa fuera de la ventana de soporte siempre que actualices dentro de ese periodo.
