## Reclamación de actor del informe {#report-actor-claim}

Las solicitudes de creación de informes incluyen la cabecera opcional `x-tuist-actor-id` solo cuando estableces explícitamente `TUIST_ACTOR_ID` con una etiqueta con ámbito de organización, por ejemplo `TUIST_ACTOR_ID=employee-123 tuist inspect build`. No se envía ninguna etiqueta por defecto y Tuist no detecta los nombres de usuario del sistema operativo. Un `TUIST_ACTOR_ID` vacío omite el identificador informado, pero no elimina la identidad verificada basada en credenciales. Los identificadores deben ser de 1 a 128 bytes de caracteres ASCII imprimibles que no sean espacios; las anulaciones no válidas se omiten sin recurrir a un valor alternativo. Si un proxy personalizado rechaza cabeceras desconocidas, opta por no participar mediante la anulación de entorno vacía.

Las credenciales individuales verificadas tienen prioridad; los identificadores informados por el cliente se muestran como **No verificado** y nunca conceden permisos ni se vinculan automáticamente a usuarios. Los identificadores son visibles para cualquiera que pueda ver los informes del proyecto, incluidos los espectadores públicos cuando el proyecto es público, y se incluyen en las exportaciones de datos, así que no incluyas secretos. Esto se aplica a los informes de compilación, pruebas y eventos de comandos. Los servidores antiguos ignoran la cabecera opcional y los nuevos aceptan clientes antiguos sin ella. Los nuevos informes con token compartido sin identificador muestran **Desconocido**, en lugar de la organización publicadora; los informes históricos conservan su atribución anterior. Los listados de compilaciones y pruebas distinguen entre usuarios verificados e identificadores informados no verificados. La autenticación sigue siendo necesaria a menos que la instancia autoalojada habilite explícitamente los informes sin credenciales y el cliente descubra esa política.

### Acciones posteriores del esquema {#actor-claim-post-actions}

Las reclamaciones de actor están desactivadas por defecto. Para configurar una para una acción posterior del esquema, establece `TUIST_ACTOR_ID` en ese script en lugar de depender de las exportaciones del shell. Xcode iniciado desde el Dock no hereda las variables de `~/.zshrc`. Para suprimir explícitamente una reclamación configurada con Homebrew, usa:

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
