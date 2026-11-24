---
{
  "title": "Instantáneas",
  "titleTemplate": ":title · Funcionalidades · Guías · Tuist",
  "description": "Detecta regresiones visuales en proyectos de Xcode y Gradle: Tuist almacena tus imágenes de instantáneas, compara cada pull request con su línea base y te permite aprobar o rechazar los cambios desde el panel o la pull request."
}
---
# Snapshots {#snapshots}

> [!IMPORTANT]
> **Solo por invitación**
>
> Los snapshots están disponibles solo por invitación. [Ponte en contacto](mailto:contact@tuist.dev) o escríbenos en el [Slack de la comunidad](https://slack.tuist.dev) para solicitar acceso para tu cuenta.

Los tests de snapshot renderizan tu interfaz de usuario en imágenes y las comparan con imágenes de referencia para detectar regresiones visuales. En lugar de confirmar esas imágenes de referencia en tu repositorio, subes a Tuist las imágenes que genera cada ejecución de tests. Tuist las compara con una **línea base**, muestra los cambios en el dashboard y hace fallar la ejecución hasta que alguien apruebe los cambios.

- Sin imágenes de referencia en Git, así que los checkouts se mantienen pequeños y nadie tiene que resolver conflictos en archivos PNG.
- Los revisores ven los cambios junto al código: lado a lado, como un diff, o con superposiciones tipo wipe u onion skin.
- Los cambios se aprueban o rechazan en el dashboard o en la pull request, y la aprobación se convierte en la nueva línea base cuando la rama se fusiona.

## Cómo funciona {#how-it-works}

1. Tus tests generan imágenes, por ejemplo de cada preview de SwiftUI o Compose.
2. El CLI de Tuist o el plugin de Gradle las suben como una **compilación de snapshot** del commit actual.
3. Tuist elige la línea base: la compilación de tu rama principal en el commit desde el que partió tu rama.
4. Cada imagen se compara con su línea base y se marca como cambiada, añadida, eliminada o sin cambios.
5. La compilación recibe un veredicto:

| Veredicto | Ejecución | Cuándo |
| --- | --- | --- |
| Línea base | Pasa | La compilación es de la rama principal, así que las compilaciones posteriores comparan con ella. |
| Aprobada | Pasa | Ninguna imagen cambió ni fue eliminada. Las nuevas imágenes no requieren revisión. |
| Requiere revisión | Falla | Las imágenes cambiaron o fueron eliminadas, y nadie las ha revisado aún. |
| Aprobada | Pasa | Alguien aprobó los cambios. |
| Rechazada | Falla | Alguien rechazó los cambios. |

Las compilaciones se comparan dentro de un **conjunto**, como `ios-iphone` o `android-phone`. Usa un conjunto por configuración de dispositivo, para que las imágenes renderizadas a distintos tamaños nunca se comparen entre sí.

## Configuración {#set-up}

Elige la integración para tu proyecto:

<.home_cards>
  <.home_card
    title="Xcode"
    details="Haz snapshot de cada preview de SwiftUI de un proyecto de Xcode con tuist xcodebuild test."
    link="/guides/features/snapshots/xcode"
/>
  <.home_card
    title="Proyectos generados"
    details="Haz snapshot de cada preview de SwiftUI de un proyecto generado por Tuist con tuist test."
    link="/guides/features/snapshots/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Haz snapshot de cada preview de Compose, o sube lo que graben Paparazzi y Roborazzi, con el plugin de Gradle de Tuist."
    link="/guides/features/snapshots/gradle"
/>
</.home_cards>

## Revisar cambios en el dashboard {#dashboard}

Cada compilación de snapshot tiene una página bajo **Tests → Snapshots** en el dashboard de tu proyecto. Muestra el veredicto de la compilación, la rama, el commit, la pull request y la línea base, y lista las imágenes por estado y grupo. Usa **Aprobar cambios** o **Rechazar cambios** para revisar la compilación. Puedes cambiar la revisión más tarde.

![Una compilación de snapshot que requiere revisión, con una imagen cambiada lado a lado con su línea base](/images/guides/features/snapshots/review.png)

Alterna entre **Lado a lado**, **Diff**, que resalta los píxeles cambiados, **Wipe**, que desliza entre la línea base y la nueva imagen, y **Onion**, que funde una en la otra. Cada imagen se puede abrir en pantalla completa.

![El modo wipe, deslizándose entre la línea base y la nueva imagen](/images/guides/features/snapshots/wipe.png)

## Revisar cambios en la pull request {#pull-request}

Con la <.localized_link href="/guides/integrations/gitforge/github">app de GitHub</.localized_link> instalada, cada compilación de snapshot de una pull request recibe un check llamado `tuist/snapshots (<set>)`. Mientras los cambios necesiten revisión, o después de que un revisor los rechace, el check falla y bloquea la fusión si es obligatorio:

![La caja de fusión de la pull request con el check de snapshots fallando porque los cambios fueron rechazados](/images/guides/features/snapshots/github-pr-checks.png)

El check cuenta las imágenes cambiadas, añadidas y eliminadas del conjunto y enlaza a la compilación en el dashboard. Aprueba o rechaza los cambios desde la página del check, sin salir de GitHub. El check se actualiza con el nombre del revisor, y una compilación rechazada aún puede aprobarse más tarde.

![El check de snapshots en GitHub después de que los cambios fueron rechazados, con el botón para aprobarlos](/images/guides/features/snapshots/github-check-run.png)

Aprobar no vuelve a ejecutar tus tests: hace pasar el check. Las compilaciones posteriores de la misma rama mantienen la aprobación siempre que tengan exactamente los mismos cambios, así que volver a ejecutar la CI o hacer push de un commit que no toque las imágenes revisadas también pasa. Cualquier otro cambio en las imágenes necesita una nueva revisión. Una vez que la rama se fusiona, la compilación de la rama principal se convierte en la nueva línea base.
