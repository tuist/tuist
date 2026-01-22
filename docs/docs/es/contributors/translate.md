---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Traducir {#translate}

Los idiomas pueden ser una barrera para la comprensión. Queremos asegurarnos de
que Tuist sea accesible para el mayor número de personas posible. Si hablas un
idioma que Tuist no admite, puedes ayudarnos traduciendo las distintas
superficies de Tuist.

Dado que el mantenimiento de las traducciones es un esfuerzo continuo, añadimos
idiomas a medida que vemos que hay colaboradores dispuestos a ayudarnos a
mantenerlos. Actualmente se admiten los siguientes idiomas:

- Inglés
- Coreano
- Japonés
- Ruso
- Chino
- Español
- Portugués

::: tip REQUEST A NEW LANGUAGE
<!-- -->
Si crees que Tuist se beneficiaría de admitir un nuevo idioma, crea un nuevo
[tema en el foro de la comunidad](https://community.tuist.io/c/general/4) para
debatirlo con la comunidad.
<!-- -->
:::

## Cómo traducir {#how-to-translate}

Tenemos una instancia de [Weblate](https://weblate.org/en-gb/) ejecutándose en
[translate.tuist.dev](https://translate.tuist.dev). Puede dirigirse al
[proyecto](https://translate.tuist.dev/engage/tuist/), crear una cuenta y
empezar a traducir.

Las traducciones se sincronizan con el repositorio de origen mediante
solicitudes de extracción de GitHub, que los mantenedores revisarán y
fusionarán.

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
Weblate segmenta los archivos para vincular los idiomas de origen y destino. Si
modifica el idioma de origen, romperá el vínculo y la reconciliación podría dar
resultados inesperados.
<!-- -->
:::

## Directrices {#guidelines}

Las siguientes son las pautas que seguimos al traducir.

### Contenedores personalizados y alertas de GitHub {#custom-containers-and-github-alerts}

Al traducir [contenedores
personalizados](https://vitepress.dev/guide/markdown#custom-containers), traduce
solo el título y el contenido **, pero no el tipo de alerta**.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### Títulos de encabezados {#heading-titles}

Al traducir encabezados, traduce solo el título, pero no el identificador. Por
ejemplo, al traducir el siguiente encabezado:

```markdown
# Add dependencies {#add-dependencies}
```

Debe traducirse como (tenga en cuenta que el identificador no se traduce):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
