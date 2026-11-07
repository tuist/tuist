## Metadatos personalizados {#custom-metadata}

Puedes adjuntar metadatos a las compilaciones mediante variables de entorno para mejorar el filtrado.

### Variables de entorno

| Variable | Formato | Descripción |
|----------|--------|-------------|
| `TUIST_BUILD_TAGS` | Separado por comas | Varias etiquetas en una sola variable. |
| `TUIST_BUILD_VALUE_*` | Valor único | Par clave-valor donde el sufijo es la clave. |

### Ejemplos

Establece estos valores en tu CI o en tu shell antes de invocar tu compilación:

```sh
export TUIST_BUILD_TAGS="nightly,ios-team,release-candidate"
```

```sh
export TUIST_BUILD_VALUE_TICKET="PROJ-1234"
export TUIST_BUILD_VALUE_PR_URL="https://github.com/myorg/myrepo/pull/123"
```
