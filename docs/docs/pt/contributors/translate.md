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

> [!TIP] REQUEST A NEW LANGUAGE
> If you believe Tuist would benefit from supporting a new language, please create a new [topic in the community forum](https://community.tuist.io/c/general/4) to discuss it with the community.

## How to translate

We use [Crowdin](https://crowdin.com/) to manage the translations. First, go to the project that you want to contribute to:

- [Documentation](https://crowdin.com/project/tuist-documentation)
- [Website](https://crowdin.com/project/tuist-documentation)

You'll need an account to start translating. You can sign in with GitHub. Once you have access, you can start translating. You'll see the list of resources that are available for translation. When you click on a resource, the editor will open, and you'll see a split view with the resource in the source language on the left and the translation on the right. Translate the text on the right and save your changes.

As translations are updated, Crowdin will push them automatically to the right repository opening a pull request, which the maintainers will review and merge.

> [!IMPORTANT] DON'T MODIFY THE RESOURCES IN THE TARGET LANGUAGE
> Crowdin segments the files to bind source and target languages. If you modify the source language, you'll break the binding, and the reconciliation might yield unexpected results.

## Guidelines

The following are the guidelines we follow when translating.

### Custom containers and GitHub alerts

When translating [custom containers](https://vitepress.dev/guide/markdown#custom-containers) or [GitHub Alerts](https://docs.github.com/pt/get-started/writing-on-github/getting-started-with-writing-and-formatting-on-github/basic-writing-and-formatting-syntax#alerts), only translate the title and the content **but not the type of alert**.

:::details Example with GitHub Alert

````markdown
    > [!WARNING] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...

    // Instead of
    > [!주의] 루트 변수
    > 매니페스트의 루트에 있어야 하는 변수는...
    ```
:::


::: details Example with custom container
```markdown
    ::: warning 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::

    # Instead of
    ::: 주의 루트 변수\
    매니페스트의 루트에 있어야 하는 변수는...
    :::
````

:::

### Heading titles

When translating headings, only translate tht title but not the id. For example, when translating the following heading:

```markdown
# Add dependencies {#add-dependencies}
```

It should be translated as (note the id is not translated):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
