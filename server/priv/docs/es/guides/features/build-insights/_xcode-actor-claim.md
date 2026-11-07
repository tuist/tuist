## Reclamación de actor del informe {#report-actor-claim}

Las solicitudes de creación de informes incluyen la cabecera opcional `x-tuist-actor-id` solo cuando estableces explícitamente `TUIST_ACTOR_ID` con una etiqueta del ámbito de la organización, por ejemplo `TUIST_ACTOR_ID=employee-123 tuist inspect build`. Por defecto no se envía ninguna etiqueta y Tuist no detecta los nombres de usuario del sistema operativo. Un valor vacío en `TUIST_ACTOR_ID` omite el identificador informado, pero no elimina la identidad verificada basada en credenciales. Los identificadores deben tener entre 1 y 128 bytes de caracteres ASCII imprimibles que no sean espacios; las anulaciones no válidas se omiten sin recurrir a valores predeterminados. Si un proxy personalizado rechaza cabeceras desconocidas, opta por no participar usando la anulación de entorno vacía.

Las credenciales individuales verificadas tienen prioridad; los identificadores informados por el cliente se muestran como **No verificado** y nunca otorgan permisos ni se vinculan automáticamente a usuarios. Los identificadores son visibles para cualquiera que pueda ver los informes del proyecto, incluidos los espectadores públicos cuando el proyecto es público, y se incluyen en las exportaciones de datos, así que no incluyas secretos. Esto se aplica a los informes de compilación, pruebas y eventos de comandos. Los servidores antiguos ignoran la cabecera opcional y los servidores nuevos aceptan clientes antiguos sin ella. Los nuevos informes con token compartido que no tienen identificador muestran **Desconocido**, en lugar de la organización que los publica; los informes históricos conservan su atribución anterior. Los listados de compilaciones y pruebas distinguen a los usuarios verificados de los identificadores informados no verificados. La autenticación sigue siendo necesaria a menos que la instancia autoalojada habilite explícitamente los informes sin credenciales y el cliente detecte esa política.

### Acciones posteriores del esquema {#actor-claim-post-actions}

Las reclamaciones de actor están desactivadas por defecto. Para configurar una para una acción posterior de un esquema, establece `TUIST_ACTOR_ID` en ese script en lugar de depender de las variables de entorno del shell. Xcode lanzado desde el Dock no hereda las variables de `~/.zshrc`. Para suprimir explícitamente una reclamación configurada con Homebrew, usa:

```sh
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"
export TUIST_ACTOR_ID=""
tuist inspect build
```

Con Mise, anula el valor después de que Mise cargue su entorno:

```sh
$HOME/.local/bin/mise x -C "$SRCROOT" -- env TUIST_ACTOR_ID="" tuist inspect build
```

Usa una etiqueta explícita en lugar del valor vacío para participar.
