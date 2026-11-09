---
title: "Continuous localization with L10N.md"
category: "engineering"
tags: ["engineering", "localization", "i18n", "llm", "glossia", "build-systems"]
excerpt: "How Tuist uses Glossia and L10N.md for continuous localization, with inherited context, incremental translation, and repository-aware validation."
author: pepicrft
---

*Hola, soy Pedro. Schön, dass du da bist. नमस्ते, आपसे मिलकर खुशी हुई। Que bom ter você por aqui.*

The world of languages is diverse, and **languages are a tool for connection**. At Tuist, we want people to feel welcome asking questions, sharing what they know, and helping shape the product in their own language. Our community spans the world, including Korea, Turkey, Latin America, and China, and using English should not be a condition for taking part. That's why we care about making every surface of the product speak the languages of the communities we support, from the dashboard and our apps to the website and documentation. Someone should be able to learn about a feature, try it, and understand an error message without having to switch to English halfway through.

We've always cared about this, but the localization tools we tried never kept up with how quickly we ship. A new feature can bring interface copy and documentation changes, with an announcement to follow. Our small team needs to keep all of that current in each language as development continues, and localization kept becoming a separate queue of work that someone had to coordinate.

Earlier this year, we [wrote about an experiment with LLM-powered localization](/blog/2026/04/28/localization-with-llms). Since then, we've started using [Glossia](https://github.com/glossia/glossia) at Tuist. Glossia is a **personal open-source project of mine**, separate from Tuist, where I've been exploring how translation could keep up with software development. I call the approach **continuous localization**: the system watches for changes, identifies which translations they affect, and translates and validates them in the background. Tuist gives me a real codebase and a multilingual community to learn from, although I still merge the translation pull requests myself.

## Speed, quality, and cost

For a long time, we felt caught between **speed, quality, and cost**. If you wanted translations to be ready as soon as content appeared, with someone who understood the product taking care over the wording, you could bring translators into the team. They could follow development closely and ask questions while the work was happening. That is appealing, but it is also a substantial ongoing investment, especially when each additional language needs attention. For a team our size, it put a limit on how many communities we could support well.

Working with external translators made it possible to buy that expertise without maintaining an in-house team for every language. Good translation still cost money, though, and batching the work introduced a delay. While a batch was being translated, the software kept changing. We would have to hold a release back or ship some content untranslated and catch up later. A product that switches languages between one screen and the next feels unfinished, and users have different expectations about how much of that inconsistency they are willing to accept. Translating a product once did not resolve the delivery problem.

Automatic translation gave us speed at a lower cost, with less control over the result. It could help someone get the gist of a documentation page, but a short button label leaves much less room for ambiguity. A technical term might need to remain in English, a familiar expression might sound strange in another language, and marketing copy should still sound like us. We needed a way to influence those choices across the product and to improve them when someone pointed out a mistake. Asking a generic translation engine for another pass did not give us much of a system for doing that.

My wife studied translation and loves languages, so these tradeoffs have also been the subject of many conversations at home. As LLMs became more capable, we started wondering whether models trained on so much language could change the setup. Could we keep translations moving with software, retain control over their quality, and make the cost low enough that adding a language would be a practical decision for a small team? Those conversations led me to start experimenting with Glossia.

## A model is not a localization system

A script that sends a file to an LLM with “translate this to Japanese” is a good starting point. You can get useful results quickly, and it gives you something concrete to try with your content. Once you run it regularly, though, you start needing more: a way to translate only what changed, somewhere to keep context that applies across files, and checks that the output still works in the repository. A change to the glossary should also update translations whose source text has not changed. Each of those requirements adds work around the model call, until you are building a localization system rather than a script that passes files to an LLM.

My expectation is that producing a translation will become an increasingly solved part of the problem, much as producing code is becoming easier. That does not mean every translation is correct today, or that better models remove the need for judgment. Even a model that wrote excellent prose every time would need a surrounding system to decide which content to translate, give it the right context, integrate its output, and notice when an earlier translation needed to change. Those responsibilities become more important as the amount of content and the number of languages grow.

In software engineering, people are exploring that surrounding system through [agent harnesses](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), feedback loops, and increasingly autonomous software factories. Deciding how an agent gets context and finds out that its work is wrong has become an engineering problem of its own. I wanted to explore those questions in localization, where a fluent model response can look convincing while violating a constraint that was never made explicit. Better wording alone would not give me enough confidence to let a system update a repository on its own.

In our setup at Tuist, Glossia watches changes landing in `main` and sends the affected content through that process in the background. The lower cost and reduced coordination have made it more practical for us to support new languages. We recently added Arabic alongside support for [right-to-left layouts](https://developer.mozilla.org/en-US/docs/Web/HTML/Global_attributes/dir). The layout work still required product engineering, but we could add the language without first creating a new manual translation workflow and finding someone to keep it moving after every release.

![Tuist's marketing page in Arabic, with right-to-left navigation and layout](/marketing/images/blog/2026/11/06/continuous-localization/arabic-marketing.webp)

## Translation context with L10N.md

Glossia takes its context from [`L10N.md` files](https://glossia.ai/docs/reference/l10n-md), much as coding agents read [`AGENTS.md`](https://agents.md). These are Markdown files with frontmatter, kept alongside the content they describe. At the root of the repository, we can explain our voice, our audience, and the product names that should stay unchanged. A file deeper in the tree adds guidance for its own area. Marketing copy can be conversational, while an error message needs to help someone understand what went wrong. Both inherit the general context without having to duplicate it.

That hierarchy also supports language-specific guidance at each level through `L10N/<locale>.md` files. We might have a convention for Spanish throughout the repository and a more specific instruction for Spanish interface copy in one part of it. The model receives the applicable context from the general to the specific, including the relevant locale guidance. This lets us describe how we want Tuist to sound overall while still giving a particular language or part of the codebase the attention it needs.

![Repository layout showing root and server L10N.md context inherited by Spanish and Japanese locale overrides](/marketing/images/blog/2026/11/06/continuous-localization/context-overrides.webp)

Here is a shortened excerpt from [Tuist's `server/L10N.md`](https://github.com/tuist/tuist/blob/main/server/L10N.md):

```yaml
---
sources:
  "priv/gettext/*.pot": "priv/gettext/{locale}/LC_MESSAGES/{basename}.po"
targets:
  ar: "Arabic"
  es: "Spanish"
  ja: "Japanese"
glossary:
  - source: cache miss
    definition: Requested data was not found in the cache. This is not a failed build or test.
  - source: flaky tests
    definition: Tests that pass and fail intermittently without relevant code changes.
---
```

The real file includes our other target languages and more context. The [glossary in the frontmatter](https://glossia.ai/docs/reference/glossary) establishes what terms mean, and locale files can supply their preferred translations. For example, our [Spanish glossary](https://github.com/tuist/tuist/blob/main/server/L10N/es.md) uses `tests` for “tests” and `funcionalidades` for “features.” Our [Japanese guidance](https://github.com/tuist/tuist/blob/main/server/L10N/ja.md) asks for established developer vocabulary and natural Japanese sentence structure, rather than carrying over English word order. That gives the model information it cannot reliably infer from an isolated string. A cache miss must not turn into a failed build, and “shipping” in our content usually means delivering software rather than moving a parcel.

We also want to choose models according to the language being translated. Models are not trained equally across languages, and the one whose Japanese output works best for a team might not be its preferred choice for Portuguese. Glossia supports locale-specific model choices so that those decisions can be made independently. The rest of the workflow can stay the same while we learn which model works well for a language and adjust the routing. Improving the translation should not require rebuilding the integration around a different provider.

## Incremental translation, borrowed from build systems

Sending everything to a model on every commit would quickly become expensive, so Glossia needs to know **which translations can be skipped**. Working on build systems at Tuist has given me years of experience with dependency graphs and incremental execution, and I wanted to apply that experience to languages. A compiler should not rebuild an unchanged target whose inputs are still the same. A localization system should be able to make an equivalent decision about content, while accounting for the instructions given to a model as well as the source text.

A translation depends on its source text and the applicable context, including language-specific guidance, glossary entries, and generation settings. Context can also live outside the repository: a shared voice or terminology definition in the Glossia platform can affect content in the repository. Glossia tracks these relationships as a dependency graph and records its translation baselines in lockfiles under `.glossia/`. Here is an excerpt from the Spanish lockfile for our marketing strings, with hashes shortened and the other nodes and detailed metadata omitted:

```json
{
  "baseline_schema_version": 1,
  "hash": "96b2b2ed806a...",
  "hash_tree": {
    "root": {
      "children": [
        {
          "hash": "b91aa5f24722...",
          "kind": "source",
          "label": "server/priv/gettext/marketing.pot"
        },
        {
          "hash": "4d5c44a3e749...",
          "kind": "context_bundle",
          "label": "context"
        }
      ]
    }
  }
}
```

These are **[Merkle trees](https://en.wikipedia.org/wiki/Merkle_tree)**: each node's hash incorporates its own metadata and the hashes of its children. Change a leaf, such as the Spanish context, and the hashes change all the way up to the root. Comparing root hashes tells us whether the translation's inputs are unchanged; comparing the branches tells us where they differ. Glossia's [implementation](https://github.com/glossia/glossia/blob/main/app/lib/glossia/translations/locks.ex) applies this to source content, generation settings, and context, so a glossary update can invalidate a translation just as a changed dependency invalidates a build artifact.

The full context subtree includes repository guidance and organization-level voice and terminology. Keeping those individual nodes lets us explain **why a translation was triggered**, with more detail than a single opaque hash could provide. We can distinguish a source edit from a change to our Spanish guidance or an update to shared voice in the platform. When a translation runs unexpectedly, we can inspect the inputs that caused it, just as we would investigate why a build target was invalidated.

Unchanged inputs let us skip the translation, while changes invalidate the affected output. A change to Spanish guidance should not force Japanese content through the model; a shared voice change can have a much wider reach, even if nobody edited the source strings. This also gives us a way to improve existing translations by changing context, instead of waiting for their English source to be touched. Applying what I've learned about build systems to languages has been one of the most enjoyable parts of the project, and it helps keep the cost of continuous translation manageable.

## Translated does not mean ready to merge

One of our frustrations with previous setups was where their responsibility ended. They would pull content out of the repository, or have us push it into another system, do the translation there, and send it back as a pull request. The returned content had not necessarily been checked against the repository that would consume it. A developer then had to decide whether to merge changes in languages they might not read, wait for CI to tell them whether the files integrated, and investigate if something broke. It is a difficult position to put someone in when the whole point was to take translation work off their plate.

Taking responsibility for integration means providing compute and working with an unfamiliar repository's toolchain, which helps explain why translation tools often stop at that boundary. I wanted Glossia to take on that work too. Alongside translation, it uses an LLM to look at the codebase, determine which validations are appropriate for the content changes, and run them. **Validation happens inside the translation workflow**, before the result comes back to us. CI remains an independent check, rather than our first opportunity to discover that the generated files are invalid.

Some of the problems are familiar from generating code. If you hand an entire JSON file to a model and ask it to translate the contents, the result can contain good prose and invalid syntax. There is no reason to leave that entirely to model judgment when file-format handling and a parser can constrain and check it. Interpolation variables, links, and application-specific requirements introduce other constraints we need to account for. Passing those checks still would not establish that the Japanese sounds natural, so we also need feedback that addresses the language itself. Different mistakes call for different kinds of validation.

I would eventually like to trust the system enough to let translations land directly in `main`. Seeing people explore that level of autonomy for coding makes me curious about what it would take for localization. **Glossia still opens pull requests at Tuist, and I still merge them.** Models can hallucinate or miss instructions, and I expect to keep discovering cases Glossia does not handle well. Each of those cases needs investigation and a change to the process so the same mistake is less likely next time. In coding, that can mean an adversarial review loop; I'm exploring what an equivalent process should look like for translations before removing the manual merge step.

![A Glossia translation pull request on GitHub, showing source commits, translation progress, and a per-language summary](/marketing/images/blog/2026/11/06/continuous-localization/glossia-pull-request.webp)

[This translation pull request](https://github.com/tuist/tuist/pull/15450) shows the information Glossia brings back to the repository: the source commits it is catching up with, progress through the translation run, and a breakdown by language.

## Where people fit

I'm also interested in **how people can contribute when translation happens continuously**. Better models will help, but they will not automatically know how our community talks about the product. Someone using Tuist in Japanese might notice wording that is technically understandable but awkward. A Spanish-speaking contributor might know that a term we chose means something different in this context. Those observations should be able to improve the system, including content that has already been translated.

[Lee Young-Jun](https://www.linkedin.com/in/gamehelper/), a member of our Korean community, keeps asking me how he can help with the system. Every time, I feel we are missing the tools to make that easy. **Someone should be able to give feedback where they encounter the text**, without knowing which file contains it or how to capture the surrounding context for a translator or a model. They already know what sounds wrong and can help us understand why; locating a string in a codebase should not be the price of contributing that knowledge.

It feels crazy that, in 2026, this is still an unresolved problem in so many translation systems. I think part of the reason is that we keep looking at localization through the same lens we used thirty years ago: extract strings, send them somewhere to be translated, then import the results. That workflow gives us somewhere to manage files and translation jobs, but it does little for someone like Lee who wants to help while using the product. I'd like Glossia to make that contribution possible without requiring him to learn how our localization pipeline works.

Professional translators can bring their editorial judgment to that work, and I also want to make room for people who know a language and the product well without being translators by profession. They should be able to help with terminology or voice without taking on entire files of strings. Many of those people will not be developers, so asking them to navigate a repository and open a Git pull request would be a poor interface. This is why voice, glossary, and context also live in the Glossia platform: they need to be accessible to the people best placed to shape them. The system should help turn feedback about a phrase into useful guidance, rather than expecting contributors to arrive with that guidance already written.

The contribution model I'd like to reach resembles a pull request, but for language guidance. An external contributor could propose a glossary correction or a change to how the product should sound, and the team could review that proposal before accepting it. Acceptance would update the context that the translation system uses. Because the graph includes those dependencies, the change could trigger the affected translations automatically, even with no source-code changes. For example, an accepted Spanish terminology correction could cause the relevant Spanish content to be translated again, while leaving other languages alone. That would give a contributor a way to improve translations beyond the single phrase they happened to encounter.

## Localization that moves with the product

At Tuist, continuous localization is already making it easier to keep translations current and support more languages. We still review and merge the results. With Glossia, I want to keep working toward a setup where the system can take responsibility for delivery and people can contribute their knowledge of a language without having to manage a translation queue. The contribution workflow described above is still something I want to build toward.

I'd love to see more products embrace the diversity of languages as we're trying to do at Tuist. There are people who would use what you're building, contribute to it, or feel more at home in its community if it spoke their language. If you'd like to make that happen in your own product, [get in touch](mailto:pedro@tuist.io). I'm happy to share what we've learned and help you find a way to make localization work for your team.
