---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "This document describes the principles that guide the development of Tuist."
}
---
# Translate {#translate}

Languages can be barriers to understanding. We want to make sure that Tuist is accessible to as many people as possible. If you speak a language that Tuist doesn't support, you can help us by translating the various surfaces of Tuist.

Since maintaining translations is a continuous effort, we add languages as we see contributors willing to help us maintain them. The following languages are currently supported:

- English
- Korean
- Japanese
- Russian
- Chinese
- Spanish
- Portuguese

::: tip REQUEST A NEW LANGUAGE
<!-- -->
If you believe Tuist would benefit from supporting a new language, please create a new [topic in the community forum](https://community.tuist.io/c/general/4) to discuss it with the community.
<!-- -->
:::

## How to translate {#how-to-translate}

We have an instance of [Weblate](https://weblate.org/en-gb/) running at [translate.tuist.dev](https://translate.tuist.dev).
You can head to [the project](https://translate.tuist.dev/engage/tuist/), create an account, and start translating.

Translations are synchronized back to the source repository using GitHub pull requests which maintainers will review and merge.

::: warning DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
<!-- -->
Weblate segments the files to bind source and target languages. If you modify the source language, you'll break the binding, and the reconciliation might yield unexpected results.
<!-- -->
:::

## Guidelines {#guidelines}

The following are the guidelines we follow when translating.

### Custom containers and GitHub alerts {#custom-containers-and-github-alerts}

When translating [custom containers](https://vitepress.dev/guide/markdown#custom-containers) only translate the title and the content **but not the type of alert**.

```markdown
<!-- -->
::: warning 루트 변수
<!-- -->
매니페스트의 루트에 있어야 하는 변수는...
<!-- -->
:::
```

### Heading titles {#heading-titles}

When translating headings, only translate tht title but not the id. For example, when translating the following heading:

```markdown
# Add dependencies {#add-dependencies}
```

It should be translated as (note the id is not translated):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
