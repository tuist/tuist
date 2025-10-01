---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Traducir

Los idiomas pueden ser barreras para la comprensión. Queremos asegurarnos de que
Tuist sea accesible al mayor número de personas posible. Si hablas un idioma que
Tuist no admite, puedes ayudarnos traduciendo las distintas superficies de
Tuist.

Dado que el mantenimiento de las traducciones es un esfuerzo continuo, añadimos
idiomas a medida que vemos colaboradores dispuestos a ayudarnos a mantenerlos.
Actualmente se admiten los siguientes idiomas:

- Inglés
- Coreano
- Japonés
- Ruso
- Chino
- Español
- Portugués

> [CONSEJO] SOLICITAR UN NUEVO IDIOMA Si crees que Tuist se beneficiaría del
> soporte de un nuevo idioma, por favor crea un nuevo [tema en el foro de la
> comunidad](https://community.tuist.io/c/general/4) para discutirlo con la
> comunidad.

## Cómo traducir {#how-to-translate}

Tenemos una instancia de [Weblate](https://weblate.org/en-gb/) funcionando en
[translate.tuist.dev](https://translate.tuist.dev). Puedes dirigirte a [el
proyecto](https://translate.tuist.dev/engage/tuist/), crear una cuenta y empezar
a traducir.

Las traducciones se sincronizan con el repositorio fuente mediante pull requests
de GitHub que los mantenedores revisarán y fusionarán.

> [IMPORTANTE] NO MODIFIQUE LOS RECURSOS EN EL IDIOMA DE DESTINO Weblate
> segmenta los archivos para enlazar los idiomas de origen y de destino. Si
> modifica el idioma de origen, romperá el enlace y la reconciliación podría dar
> resultados inesperados.

## Directrices {#guidelines}

A continuación se indican las directrices que seguimos al traducir.

### Contenedores personalizados y alertas de GitHub {#custom-containers-and-github-alerts}

Al traducir [contenedores
personalizados](https://vitepress.dev/guide/markdown#custom-containers) o
[alertas de
GitHub](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts),
sólo traduce el título y el contenido **pero no el tipo de alerta**.

::: detalles Ejemplo con alerta GitHub
```markdown
    > [!WARNING] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...

    // Instead of
    > [!주의] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...
    ```
:::


::: details Example with custom container
```
    ::: warning 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::

    # Instead of
    ::: 주의 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::
```
:::

### Heading titles {#heading-titles}

When translating headings, only translate tht title but not the id. For example, when translating the following heading:

```
# Añadir dependencias {#add-dependencies}
```

It should be translated as (note the id is not translated):

```
# 의존성 추가하기 {#add-dependencies}
```

```
