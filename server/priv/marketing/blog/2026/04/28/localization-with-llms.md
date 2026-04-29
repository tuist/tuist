---
title: "L10N.md: localization built like we ship software"
category: "engineering"
tags: ["engineering", "localization", "i18n", "llm", "agents"]
excerpt: "Existing localization tools take content out of the repository and translate it in environments where changes can't be validated. We tried Crowdin and Weblate, none of them felt right. So we built our own system on top of LLMs, with the repository as the source of truth and a lockfile to keep things incremental."
author: pepicrft
og_image_path: /marketing/images/blog/2026/04/28/localization-with-llms/og.jpg
---

At Tuist we are building a platform team as a service. The companies and developers we serve are spread across the world, and a good portion of them work and think in languages that are not English. If we want our product to feel close to those communities, we have to meet them where they are. That is why we have been pushing for a multi-lingual product since the very beginning. The dashboard, the marketing site, the error messages, all of it.

A lot of the courage to keep investing in this comes from conversations with [María José Salmerón](https://www.linkedin.com/in/mariajosesalmeron/), who has been a continuous source of inspiration on how languages are not just a "nice to have" feature, but a real tool to reach new markets and audiences. It is easy to deprioritize localization when you are a small team with a long roadmap. Her perspective is what keeps reminding us that the cost of not doing it is much higher than it looks.

The problem is that, with a small team like ours, the cost of setting up a localization system is surprisingly high. The tools that exist today don't integrate well into the standard software development workflow. They take state and content out of the repository, hand it to translators in an environment where changes can't be validated for correctness, and ship the results back as PRs that often break our automation. When something goes wrong, tracing the change back to its root cause is painful. We tried [Crowdin](https://crowdin.com), we tried [Weblate](https://weblate.org), and none of them felt right. They were designed for a world where translation is a separate function, owned by a separate team, with a separate workflow. That is not how we ship software.

So, as engineers, we started thinking about a system for ourselves. Coding agents have pushed the cost of building this kind of internal tooling down dramatically. We wanted something that aligned with how we ship: continuously, with the repository as the source of truth for context. And because we started exploring this when LLMs were becoming popular, we had a hunch that they could be the right primitive to build on top of.

The challenge with LLMs is finding a good balance between three forces: quality, speed, and price. Speed is mostly a solved problem, and price is going down every quarter as more companies invest in inference infrastructure. Quality is the interesting part. That is the part I want to focus on here, because we have been building a system that learns from how coding agents work today: the idea of context as the lever for quality convergence.

## Meet L10N.md

The unit at the heart of our system is a file called `L10N.md`. It sits in the repository, alongside the code and the content it describes. It is plain markdown with a small piece of frontmatter on top.

The root `L10N.md` is the place where you describe the global rules: what the source language is, what is and isn't a proper noun, what should never be translated, formatting rules, tone. Here is a trimmed version of ours:

```markdown
---
source_language: "en"
---

# Global Translation Context

## Brand & Terminology
- "Tuist" is a proper noun and should never be translated.
- Technical terms should remain in English: Xcode, Swift, Gradle, API, CLI, SDK...
- Product feature names should remain in English: Binary Caching, Previews, Registry, Dashboard.

## Formatting Rules
- Preserve all HTML tags exactly as they appear in the source.
- Preserve all Elixir string interpolation variables (`%{variable_name}`) exactly as-is.
- Do not translate URLs or email addresses.
- Do not use em dashes. Use regular dashes or rephrase instead.
```

A child `L10N.md` lives next to a specific area of the codebase, and its frontmatter declares which sources it covers, where the translated artifacts go, and what target locales we want. For example, the file under `server/L10N.md`:

```markdown
---
validation: "gettext_compile"
sources:
  - "priv/gettext/*.pot"
target_path: "priv/gettext/{locale}/LC_MESSAGES"
targets:
  es: "Spanish"
  ja: "Japanese"
  ko: "Korean"
  ru: "Russian"
  zh_Hans: "Chinese (Simplified)"
  zh_Hant: "Chinese (Traditional)"
---

# Tuist Server Translation Context

## Translation Domains

- **marketing**: Public-facing marketing website. Tone should be engaging and persuasive.
- **dashboard**: Main application interface for logged-in users. Tone should be concise and clear.
- **errors**: Error messages shown across the application.
```

The idea is simple. Each `L10N.md` inherits from the ones above it, layering more specific context as you go deeper into the tree. A new contributor can read the file in the directory they are working on and understand exactly how the content under it should be translated.

On top of that, we have per-locale overrides. If there is a rule that only applies to a specific language, it goes in `L10N/{locale}.md` next to the parent `L10N.md`. For Spanish, for example, we keep things like:

```markdown
## Spanish-specific translation rules

- "Tests" should remain untranslated as "tests" (do not use "pruebas").
- "Features" should be translated as "funcionalidades".
```

Same idea. Domain-specific context lives close to the domain. Locale-specific context lives close to the locale.

## Incremental translation and the lockfile

Translating everything from scratch on every commit would be wasteful. It would also be slow and expensive. The pipeline needs to know which files have actually changed and which translations need to be regenerated. This is the kind of problem we deal with every day in build systems, so it felt natural to bring the same ideas to localization: hashing, lockfiles, and selective execution.

For every combination of source file, target locale, and the chain of `L10N.md` files that apply to it, we keep a lockfile. It looks like this:

```json
{
  "hash": "eca5aa2d8b0fb809d65d70fa9f8fbaf52a5e42cd50cafc13496da4d57d5909bf",
  "hash_tree": {
    "context": {
      "child": {
        "file": "server/L10N.md",
        "hash": "0879bdf5dc534e1a0d665bfee7247bc56bdf5c07163f270a05bd2666a07536e6",
        "locale_override": {
          "file": "server/L10N/es.md",
          "hash": "0fddcd4efd657f1b06dcfd0915245d2f172199275328cfa77c8f000c711a0361"
        }
      },
      "file": "L10N.md",
      "hash": "5d5910c58a27c289d172b18f0bca28176bf6b6a74bd894e27273f55199cd2816"
    },
    "source": {
      "file": "server/priv/gettext/default.pot",
      "hash": "4f158895cb9d1030acda934eadca7e88f621fdefbfafe0ef5db7ad3a8c51bd85"
    }
  },
  "model": "openai:gpt-4.1-mini",
  "translated_at": "2026-04-24T08:24:36.883218Z"
}
```

The pipeline rehashes every input that contributed to the translation: the source file, the chain of `L10N.md` files, the locale override. If any hash changes, that translation is invalidated and regenerated. If nothing changes, we skip it.

The set of inputs is best described as a DAG. Per translation, the inputs form a tree rooted at the source file. Across translations, the `L10N.md` nodes are shared, so the same global context node is referenced by hundreds of leaves. We hash this in a Merkle-tree style: every node carries its own SHA-256, and the top-level hash is a composite over the entire subtree. Any change at any depth propagates upward and invalidates everything that depends on it, the same way a single dirty file invalidates a build target.

The structure of the tree is what makes this powerful. We don't only know that something has to be retranslated. We know exactly **what caused it** to be retranslated. Was it a change in the source content? A change in the global context? A locale-specific rule? Each of those has different downstream effects, and being able to tell them apart matters when we want to debug quality regressions or audit a translation.

Preserving the context structure in the lockfile was a deliberate choice. The simpler design would have been to flatten everything into a single combined hash. It is easier to compute and easier to compare. But the moment you flatten, you lose the ability to diagnose **why** a translation ran. All you can say is "something upstream changed." With the tree intact, you can point at the exact node that flipped and explain the cascade. That diagnostic visibility was worth the extra structure. You can see this in practice in [this PR](https://github.com/tuist/tuist/pull/10505), where the translation regenerates and the [lockfile updates alongside it](https://github.com/tuist/tuist/pull/10505/changes#diff-add0618d42c3dd5803a08a32b11e73c698c0b2f1aa73db0aa56c7bcb02fdd05c).

## Overrides in practice

The overrides are where the system starts to feel really useful day to day. Most of the time, contributors don't need to think about them. When they do, the pattern is the same.

If you want a rule that only applies to a single locale, you add it to the locale override. We had translators consistently rendering "unit tests" as "Pruebas unitarias" in Spanish, which felt unnatural to our Spanish-speaking users. Adding one line in `server/L10N/es.md` was enough:

```markdown
- "unit tests" should remain untranslated as "unit tests" (do not use "Pruebas unitarias").
```

The next time the pipeline runs, the override is part of the context tree. The lockfile picks up the change, the affected translations are invalidated, and the new content respects the rule.

If you want a rule that only applies to a part of the codebase, you put it in the `L10N.md` closest to that area. Marketing copy needs a different tone than dashboard UI, and dashboard UI needs a different tone than error messages. Instead of trying to encode all of that in a single global file, each domain has its own `L10N.md` that builds on top of the global one. Inheritance is the mental model. You only write the rule once, in the most specific place where it applies.

## Implementation: a CI pipeline in Elixir

We implemented all of this as a CI pipeline in Elixir, our language of choice on the server, and it runs on every commit to `main`. Elixir is what we picked because it is what we are most productive in, but nothing about the design is tied to it. We could have written it in Rust, Go, Python, or anything else. The lockfile is a JSON file, the inputs are plain markdown and `.pot` files, the LLM call is an HTTP request. Pick the runtime you are most comfortable with.

What we do think is essential is running this on a CI compute environment. Once you are inside CI, you have the entire toolchain a step away. You can compile the sources after the translation, run the linter, run the gettext compilation, run a smoke test against the rendered output. That is how you close the loop with the agent. The agent produces a translation, and the same machinery your engineers use locally tells the agent whether the output is valid. A translation that breaks `mix compile` or `gettext` validation is not a translation, it is a regression, and CI is the place where that distinction is cheapest to enforce.

Right now, we don't yet have the confidence to let the pipeline merge translations directly into `main`. We need to first figure out how to close the feedback loop with the agent in a way that gives us the confidence to push directly. Until then, the pipeline opens PRs and a human reviews them.

The mental model we want contributors to internalize is that **quality won't be great initially, and that is fine.** Contributors are not expected to fix the translated content. They are expected to fix the **context** in `L10N.md` so that the next translation run produces better output. The system converges towards quality through context, not through manual edits to the translated artifacts. If you find yourself fixing the same Spanish translation over and over, that is a signal that something is missing in the context tree.

## What is next

The next challenge for us is the documentation. Our docs use a lot of proprietary components for examples, callouts, and product walkthroughs. The agent doing the translation does not need to know about those components, and trying to teach it would be expensive and brittle. We are exploring how to segment or serialize the content so the translatable parts are isolated from the proprietary pieces, and the agent only sees what it needs to.

Another challenge we already ran into is lockfile stability with `.po` files. Gettext stores the source location of every string as a comment, including the line numbers. When you add a single line above a translatable string somewhere in the codebase, the line numbers shift, the `.pot` file changes, and our hashing logic flags translations as stale even when the actual content is identical. We had to teach the pipeline to ignore the noise and only react to changes that affect the meaning of the content.

We expect models to keep getting better and cheaper, and we expect new models to emerge that are trained specifically for translation tasks. The economics of this kind of system will only improve from here. But the bigger point we want to make is that **the industry needs a different kind of localization system altogether.** One where the repository is the source of truth, where changes are reviewable like any other diff, where the context lives next to the code, and where quality converges through iteration rather than through external workflows. That is the system we are building. We are far from done, but the direction feels right.
