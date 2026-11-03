---
{
  "title": "Idiomas",
  "titleTemplate": ":title · Colaboradores · Tuist",
  "description": "Ayuda a Tuist a admitir nuevos idiomas y mejorar su contexto de localización."
}
---
# Idiomas {#translate}

Los idiomas pueden ser barreras para la comprensión. Queremos asegurarnos de que Tuist sea accesible para el mayor número posible de personas. Si hablas un idioma que Tuist aún no admite, puedes ayudar a Tuist a hablar ese idioma mejorando el contenido original en inglés y el contexto de localización que impulsa nuestra cadena de traducción.

Dado que el soporte de idiomas es un esfuerzo continuo, añadimos idiomas a medida que encontramos colaboradores dispuestos a ayudarnos a mantenerlos. Los siguientes idiomas están actualmente admitidos:

- Inglés
- Español
- Japonés
- Georgiano
- Coreano
- Ruso
- Cantonés
- Chino simplificado
- Chino tradicional

> [!TIP]
> **Solicitar un nuevo idioma**
>
> Si crees que Tuist se beneficiaría de admitir un nuevo idioma, crea un nuevo [tema en el foro de la comunidad](https://community.tuist.io/c/general/4) para debatirlo con la comunidad.


## Cómo ayudar {#how-to-translate}

El soporte de idiomas de Tuist se gestiona desde el repositorio. Los colaboradores actualizan el contenido original en inglés y el contexto de traducción, y nuestra cadena de traducción genera automáticamente los archivos localizados.

El flujo de trabajo es:

1. Actualiza el contenido original en inglés.
2. Actualiza el contexto relevante de `L10N.md` si los traductores necesitan más orientación.
3. Abre una pull request con esos cambios en el origen.
4. Una vez que los cambios se integran en `main`, el flujo de trabajo de traducción regenera los archivos `.po` de destino y abre una pull request de seguimiento con las actualizaciones traducidas.

> [!WARNING]
> **No modifiques el contenido localizado generado**
>
> No edites directamente el contenido localizado generado. Actualiza el contenido original en inglés y el contexto del idioma.


## Estructura de L10N.md {#l10n-md-structure}

Los archivos `L10N.md` definen el contexto que se envía al modelo de traducción. La forma más sencilla de entenderlos es como instrucciones de idioma con alcance específico que pueden ubicarse en distintos niveles de directorio.

Por ejemplo:

```text
.
|-- L10N.md
|-- server
|   |-- L10N.md
|   |-- L10N
|   |   `-- es.md
|   `-- priv
|       `-- gettext
|           `-- marketing.pot
```


## Contexto de directorio {#directory-context}

El script de traducción recorre desde la raíz del repositorio hasta el directorio que se está traduciendo y combina todos los archivos `L10N.md` que encuentra en esa ruta.

En el ejemplo anterior:

- `L10N.md` se aplica globalmente.
- `server/L10N.md` añade contexto específico del servidor.
- `server/L10N/es.md` añade anulaciones exclusivas para español en esa misma área.

Esto significa que puedes colocar el contexto donde corresponda:

- orientación para todo el repositorio en la raíz
- orientación específica de área en un subdirectorio
- orientación específica de idioma en `L10N/<locale>.md`
