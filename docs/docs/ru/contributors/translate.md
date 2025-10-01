---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Перевести {#translate}

Языки могут стать барьером для понимания. Мы хотим, чтобы Tuist был доступен как
можно большему числу людей. Если вы говорите на языке, который Tuist не
поддерживает, вы можете помочь нам, переведя различные поверхности Tuist.

Поскольку поддержка переводов - это постоянная работа, мы добавляем языки по
мере появления участников, готовых помочь нам в их поддержке. В настоящее время
поддерживаются следующие языки:

- Английский язык
- Корейский
- Японский
- Русский
- Китайский
- Испанский
- Португальский

> [!TIP] ЗАПРОС НА НОВЫЙ ЯЗЫК Если вы считаете, что Туист выиграет от поддержки
> нового языка, создайте новую [тему на форуме
> сообщества](https://community.tuist.io/c/general/4), чтобы обсудить это с
> сообществом.

## Как перевести {#how-to-translate}

У нас есть экземпляр [Weblate](https://weblate.org/en-gb/), запущенный по адресу
[translate.tuist.dev](https://translate.tuist.dev). Вы можете зайти на
[проект](https://translate.tuist.dev/engage/tuist/), создать учетную запись и
начать переводить.

Переводы синхронизируются с исходным репозиторием с помощью запросов на
подтягивание на GitHub, которые сопровождающие просматривают и объединяют.

> [!ВАЖНО] НЕ ИЗМЕНЯЙТЕ РЕСУРСЫ НА ЦЕЛЕВОМ ЯЗЫКЕ Weblate сегментирует файлы для
> связывания исходного и целевого языков. Если вы измените исходный язык, вы
> нарушите привязку, и согласование может дать неожиданные результаты.

## Руководящие принципы {#guidelines}

Ниже приведены рекомендации, которым мы следуем при переводе.

### Пользовательские контейнеры и оповещения GitHub {#custom-containers-and-github-alerts}

При переводе [пользовательских
контейнеров](https://vitepress.dev/guide/markdown#custom-containers) или [GitHub
Alerts](https://docs.github.com/en/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts)
переводите только заголовок и содержимое **, но не тип оповещения**.

::: детали Пример с оповещением GitHub
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
# Добавьте зависимости {#add-dependencies}
```

It should be translated as (note the id is not translated):

```
# 의존성 추가하기 {#add-dependencies}
```

```
