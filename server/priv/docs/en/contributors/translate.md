---
{
  "title": "Translate",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Help translate Tuist documentation into other languages."
}
---
# Translate {#translate}

Languages can be barriers to understanding. We want to make sure that Tuist is accessible to as many people as possible. If you speak a language that Tuist doesn't support, you can help us by translating the various surfaces of Tuist.

Since maintaining translations is a continuous effort, we add languages as we see contributors willing to help us maintain them. The following languages are currently supported:

- English
- Spanish
- Japanese
- Korean
- Russian
- Cantonese
- Simplified Chinese
- Traditional Chinese

> [!TIP]
> **Request A New Language**
>
> If you believe Tuist would benefit from supporting a new language, please create a new [topic in the community forum](https://community.tuist.io/c/general/4) to discuss it with the community.


## How to translate {#how-to-translate}

Tuist translations are driven from the repository. Contributors update the English source and the translation context, and our translation pipeline produces the localized files automatically.

The workflow is:

1. Update the English source content.
2. Update the relevant `L10N.md` context if translators need more guidance.
3. Open a pull request with those source changes.
4. After the changes land on `main`, the translation workflow regenerates the target `.po` files and opens a follow-up pull request with the translated updates.

> [!WARNING]
> **Don't Modify Generated Translation Files**
>
> Do not edit `.po` files or non-English content directly. Update the English source and the translation context instead.


## L10N.md structure {#l10n-md-structure}

`L10N.md` files define the context that is sent to the translation model. They have two parts:

- YAML frontmatter for structured configuration.
- Markdown body for human-written translation instructions.

At the repository root, `L10N.md` defines global rules such as:

- `model`: the default model used when running `translate.exs` without an override.
- `source_language`: the source language for the repository.

At the server level, `server/L10N.md` adds server-specific configuration such as:

- `validation`: the validation step for generated translations.
- `sources`: the `.pot` files that should be translated from that directory.
- `target_path`: where generated translations should be written.
- `targets`: the supported locales and their language names.

The markdown body is where you explain terminology, tone, formatting rules, product language, and domain-specific context that translators should follow.


## Directory context {#directory-context}

`L10N.md` is hierarchical. The translation script walks from the repository root down to the directory being translated and merges every `L10N.md` file it finds.

- Frontmatter from deeper files overrides parent frontmatter.
- Markdown bodies are concatenated from root to deepest directory.

This lets you add context at the level where it applies:

- Use the root `L10N.md` for repository-wide rules.
- Use `server/L10N.md` for server-wide terminology and target locales.
- Add another `L10N.md` inside a subdirectory when the context only applies to that area, for example a specific product surface or documentation section.

If the rule only applies to one language, add a locale-specific override file in an `L10N/` directory next to the relevant `L10N.md`. For example, `server/L10N/es.md` adds Spanish-only instructions.

That is useful for cases such as:

- keeping a product term untranslated in one locale
- preferring a specific regional wording
- avoiding a translation that is technically correct but unnatural for that language


## Translation pipeline {#translation-pipeline}

The translation pipeline is defined in `.github/workflows/l10n.yml`.

It runs when relevant translation inputs change on `main`, including:

- `translate.exs`
- root `L10N.md`
- `server/L10N.md`
- files under `server/L10N/`
- server `.pot` files under `server/priv/gettext/`

The workflow runs `elixir translate.exs --model "openai:gpt-4.1-mini"` and generates updated `.po` files. It also updates `.l10n` lock files, which record the source file hash and the full `L10N.md` context tree used for each translation.

Those lock files are important because they allow the pipeline to detect when a translation is stale not only because the source string changed, but also because the translation context changed. For example, updating `server/L10N.md` or `server/L10N/es.md` can trigger a re-translation even if the `.pot` file itself did not change.

In practice, if you want to improve translation quality, you should often update the relevant `L10N.md` file rather than editing generated translations by hand.


## Guidelines {#guidelines}

The following are the guidelines we follow when translating.

### Custom containers and GitHub alerts {#custom-containers-and-github-alerts}

When translating [custom containers](https://vitepress.dev/guide/markdown#custom-containers) only translate the title and the content **but not the type of alert**.

```markdown
<!-- -->
> [!WARNING]
> **루트 변수**
>
> 매니페스트의 루트에 있어야 하는 변수는...

```

### Heading titles {#heading-titles}

When translating headings, only translate the title but not the id. For example, when translating the following heading:

```markdown
# Add dependencies {#add-dependencies}
```

It should be translated as (note the id is not translated):

```markdown
# 의존성 추가하기 {#add-dependencies}
```
