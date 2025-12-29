---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Przetłumacz {#translate}

Języki mogą stanowić barierę w zrozumieniu. Chcemy mieć pewność, że Tuist jest
dostępny dla jak największej liczby osób. Jeśli mówisz w języku, którego Tuist
nie obsługuje, możesz nam pomóc, tłumacząc różne powierzchnie Tuist.

Ponieważ utrzymywanie tłumaczeń jest ciągłym wysiłkiem, dodajemy języki, gdy
widzimy współpracowników chętnych do pomocy w ich utrzymaniu. Obecnie
obsługiwane są następujące języki:

- Angielski
- Koreański
- Japoński
- Rosyjski
- Chiński
- Hiszpański
- Portugalski

::: tip ZAPYTAJ O NOWY JĘZYK
<!-- -->
Jeśli uważasz, że Tuist skorzystałby na wsparciu nowego języka, utwórz nowy
[temat na forum społeczności](https://community.tuist.io/c/general/4), aby
omówić go ze społecznością.
<!-- -->
:::

## Jak przetłumaczyć {#how-to-translate}

Mamy instancję [Weblate](https://weblate.org/en-gb/) działającą pod adresem
[translate.tuist.dev](https://translate.tuist.dev). Możesz udać się do
[projektu](https://translate.tuist.dev/engage/tuist/), utworzyć konto i
rozpocząć tłumaczenie.

Tłumaczenia są synchronizowane z powrotem do repozytorium źródłowego za pomocą
żądań ściągnięcia GitHub, które opiekunowie sprawdzają i scalają.

::: ostrzeżenie NIE MODYFIKUJ ZASOBÓW W JĘZYKU DOCELOWYM
<!-- -->
Weblate segmentuje pliki w celu powiązania języka źródłowego i docelowego. Jeśli
zmodyfikujesz język źródłowy, przerwiesz powiązanie, a uzgodnienie może
przynieść nieoczekiwane rezultaty.
<!-- -->
:::

## Wytyczne {#guidelines}

Poniżej znajdują się wytyczne, których przestrzegamy podczas tłumaczenia.

### Kontenery niestandardowe i alerty GitHub {#custom-containers-and-github-alerts}.

Podczas tłumaczenia [custom
containers](https://vitepress.dev/guide/markdown#custom-containers) tłumaczony
jest tylko tytuł i treść **, ale nie typ alertu**.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### Tytuły nagłówków {#heading-titles}

Podczas tłumaczenia nagłówków należy przetłumaczyć tylko tytuł, ale nie
identyfikator. Na przykład podczas tłumaczenia następującego nagłówka:

```markdown
# Add dependencies {#add-dependencies}
```

Powinno być przetłumaczone jako (zauważ, że identyfikator nie jest
przetłumaczony):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
