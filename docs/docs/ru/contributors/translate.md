---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Перевод {#translate}

Языки могут быть барьером для понимания. Мы хотим, чтобы Tuist был доступен как
можно большему числу людей. Если вы говорите на языке, который Tuist пока не
поддерживает, вы можете помочь проекту, переведя его различные части.

Поскольку поддержка переводов – это постоянная работа, мы добавляем новые языки,
когда появляются участники, готовые помогать в их поддержке. В настоящее время
поддерживаются следующие языки:

- Английский
- Корейский
- Японский
- Русский
- Китайский
- Испанский
- Португальский

::: tip ЗАПРОСИТЬ НОВЫЙ ЯЗЫК
<!-- -->
Если вы считаете, что поддержка нового языка могла бы быть полезна для Tuist,
пожалуйста, создайте новую [тему на форуме
сообщества](https://community.tuist.io/c/general/4), чтобы обсудить это с
участниками проекта.
<!-- -->
:::

## Как перевести {#how-to-translate}

У нас развернут инстанс [Weblate](https://weblate.org/en-gb/) по адресу
[translate.tuist.dev](https://translate.tuist.dev). Перейдите к
[проекту](https://translate.tuist.dev/engage/tuist/), создайте учётную запись и
начните перевод.

Переводы синхронизируются с исходным репозиторием через pull-реквесты GitHub,
которые мейнтейнеры проверяют и сливают.

::: warning НЕ МЕНЯЙТЕ РЕСУРСЫ В ЦЕЛЕВОМ ЯЗЫКЕ
<!-- -->
Weblate сегментирует файлы, чтобы связывать исходный и целевой языки. Если
изменить текст на исходном языке, связь нарушится, и при последующей
синхронизации могут возникнуть непредсказуемые результаты.
<!-- -->
:::

## Guidelines {#guidelines}

The following are the guidelines we follow when translating.

### Custom containers and GitHub alerts {#custom-containers-and-github-alerts}

When translating [custom
containers](https://vitepress.dev/guide/markdown#custom-containers) only
translate the title and the content **but not the type of alert**.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### Heading titles {#heading-titles}

When translating headings, only translate tht title but not the id. For example,
when translating the following heading:

```markdown
# Add dependencies {#add-dependencies}
```

It should be translated as (note the id is not translated):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
