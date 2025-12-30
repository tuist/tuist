---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Traducir {#translate}

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

::: tip REQUEST A NEW LANGUAGE
<!-- -->
Si crees que Tuist se beneficiaría de apoyar un nuevo idioma, por favor crea un
nuevo [tema en el foro de la comunidad](https://community.tuist.io/c/general/4)
para discutirlo con la comunidad.
<!-- -->
:::

## Cómo traducir {#how-to-translate}

Tenemos una instancia de [Weblate](https://weblate.org/en-gb/) funcionando en
[translate.tuist.dev](https://translate.tuist.dev). Puedes dirigirte a [el
proyecto](https://translate.tuist.dev/engage/tuist/), crear una cuenta y empezar
a traducir.

Las traducciones se sincronizan con el repositorio fuente mediante pull requests
de GitHub que los mantenedores revisarán y fusionarán.

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
Weblate segmenta los archivos para enlazar los idiomas de origen y de destino.
Si modificas el idioma de origen, romperás el enlace y la reconciliación podría
dar resultados inesperados.
<!-- -->
:::

## Directrices {#guidelines}

A continuación se indican las directrices que seguimos al traducir.

### Contenedores personalizados y alertas de GitHub {#custom-containers-and-github-alerts}

Al traducir [custom
containers](https://vitepress.dev/guide/markdown#custom-containers) sólo se
traducen el título y el contenido **pero no el tipo de alerta**.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### Títulos de las rúbricas {#heading-titles}

Al traducir títulos, traduzca sólo el título, pero no el id. Por ejemplo, al
traducir el siguiente título:

```markdown
# Add dependencies {#add-dependencies}
```

Debería traducirse como (nótese que el id no se traduce):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
