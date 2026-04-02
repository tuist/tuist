---
{
  "title": "Languages",
  "titleTemplate": ":title · Contributors · Tuist",
  "description": "Help Tuist support new languages and improve its localization context."
}
---
# Languages {#translate}

Languages can be barriers to understanding. We want to make sure that Tuist is accessible to as many people as possible. If you speak a language that Tuist does not support yet, you can help Tuist speak that language by improving the English source and the localization context that drives our translation pipeline.

Since language support is a continuous effort, we add languages as we see contributors willing to help us maintain them. The following languages are currently supported:

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


## How to help {#how-to-translate}

Tuist language support is driven from the repository. Contributors update the English source and the translation context, and our translation pipeline produces the localized files automatically.

The workflow is:

1. Update the English source content.
2. Update the relevant `L10N.md` context if translators need more guidance.
3. Open a pull request with those source changes.
4. After the changes land on `main`, the translation workflow regenerates the target `.po` files and opens a follow-up pull request with the translated updates.

> [!WARNING]
> **Don't Modify Generated Localized Content**
>
> Do not edit generated localized content directly. Update the English source and the language context instead.


## L10N.md structure {#l10n-md-structure}

`L10N.md` files define the context that is sent to the translation model. The easiest way to think about them is as scoped language instructions that can live at different directory levels.

For example:

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


## Directory context {#directory-context}

The translation script walks from the repository root down to the directory being translated and combines every `L10N.md` file it finds on that path.

In the example above:

- `L10N.md` applies globally.
- `server/L10N.md` adds server-specific context.
- `server/L10N/es.md` adds Spanish-only overrides for that same area.

That means you can place context where it belongs:

- repository-wide guidance at the root
- area-specific guidance in a subdirectory
- language-specific guidance in `L10N/<locale>.md`

