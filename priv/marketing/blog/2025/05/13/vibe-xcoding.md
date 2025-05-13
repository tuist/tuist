---
title: "Vibe Xcoding your apps"
category: "learn"
tags: ["llms", "ai", "coding"]
excerpt: "Explore how LLMs are changing the way we code and the exciting opportunities ahead as Apple brings 'vibe coding' to the Xcode ecosystem for Swift developers."
author: pepicrft
---

**This article is for iOS, macOS, and Swift developers interested in the future of AI-assisted coding, especially those working with Xcode who want to understand how LLMs and "vibe coding" could transform their development workflow. It's also relevant for technical leaders evaluating how these technologies might impact Apple's developer ecosystem.**


LLMs are here to stay.
Many developers are exploring how they can have a positive impact on how we code,
and that exploration gave birth to a concept you might have heard of: [vibe coding](https://en.wikipedia.org/wiki/Vibe_coding).
Unlike the approach to coding that we know and have used for endless years,
vibe coding proposes that you partner with an LLM letting it write and iterate on the code with context from you and the codebase you are interacting with.
Whether the future of vibe coding will have the shape that we are seeing today, and whether it'll be used for coding entire projects,
is yet to be seen since we are just at the beginning of loads of creativity and mental energy going into the space,
however, what's becoming more and more clear is that the idea of having an AI-powered copilot is here to stay,
and for certain tasks, it can indeed save you a lot of time.
Editors like [VSCode](https://code.visualstudio.com), [Cursor](https://www.cursor.com), [Zed](https://zed.dev), or [Windsurf](https://windsurf.com/editor), have built on this idea,
and are continuously exploring new UI and UX patterns that can unlock new ways of approaching code.

If you are developing apps using Xcode,
you might understandably wonder, where is vibe coding in Xcode? When will it come?
With WWDC around the corner,
we'd like to walk you through some work that's being done by the community to bridge that gap,
and take the opportunity to talk about the exciting opportunities ahead as Apple prepares to enhance the Xcode experience with AI capabilities that could surpass what we see in other ecosystems.

## A vibe-coding copilot

Vibe coding requires a chat interface that's plugged into your coding interface to write code for you, and also to gather context from the editor.
There are editors like VSCode whose extensibility allows a tight integration, and there are others like Xcode, which were not designed with a high degree of extensibility in mind,
yet it hasn't prevented developers to push the boundaries of what's possible and bring the same experience to Xcode.
Two of the most popular options are [Alex](https://www.alexcodes.app/), which presents itself as an Xcode AI Coding assistant,
and [CopilotForXcode](https://github.com/github/CopilotForXcode), an open source project developed and maintained by GitHub to integrate Xcode with their copilot offering.

It's quite impressive to see what they are capable of doing despite the limitations of the IDE, but they managed to workaround those using the system accessibility APIs.
From the two, Alex is the most actively maintained, and the experience that they provide is quite close to what you'd get from other vibe coding editors.

This opens up exciting possibilities for how Apple might approach AI integration - whether by embedding a thoughtfully designed chat interface into Xcode's UI, or by expanding the extensibility of the existing interface to allow applications like Alex to seamlessly integrate and access runtime information, which would enhance the assisted experience quite significantly. Given Apple's history of refining technologies before bringing them to market, we're eager to see their unique perspective on this space. And this brings us to the importance of having up-to-date and relevant context while interacting with the LLM.

## Context

For LLMs to do a great job at the tasks you ask them to do, they need a lot of context.
Some of that context can be provided by you via the prompts, for example if you want to vibe-code a UI, you can describe what the UI is for, what kind of data you plan to present, and even ask to populate the UI with some mock data for the purposes of prototyping.
However, that's often not enough.
The editor needs additional context to output code that can be integrated,
and in the case of an Xcode codebase,
compiled by the Swift compiler leading to an app that runs.
For example, the version of Swift that your project is using,
the structure of the Xcode project where it might need to add some files to the file group and to a sources build phase,
or the schemes that are available to build a runnable application.

This notion of LLMs talking to the outside world
is a need that [Anthropic](https://www.anthropic.com) realized,
and that led to the definition of a protocol, [Model Context Protocol (MCP)](https://modelcontextprotocol.io/introduction),
which many called the [USB-C](https://en.wikipedia.org/wiki/USB-C) of LLMs.
MCP aims to be a standard protocol for how LLMs can interact with the outside world,
either to gather additional context, or even run tasks in your system,
like building and running an app in the simulator.
While MCP got popular among code editors,
it's true that since it's coming from Anthropic,
there are some companies like OpenAI that are hesitant to adopt it,
and others that are proposing new protocols,
leading to a bit of an unfortunate situation for the ecosystem where there are multiple protocols for achieving the same thing.

The lack of MCP support in Alex (CopilotForXcode just [announced support for it](https://x.com/jialuogan/status/1922205712039461028)) hasn't prevented the community from going ahead and building MCP servers for Xcode app developers.
From all of them, one that's getting a lot of traction and it's quite actively developed is [Cameron Cooke](https://github.com/cameroncooke)'s [XcodeBuildMCP](https://github.com/cameroncooke/XcodeBuildMCP),
which you can plug into [Claude desktop](https://claude.ai/download) or other code editors like Zed or Cursor.
With it you can do things like building and running an app,
or managing your simulators.
Some of this functionality is already built into Alex, 
but once they support MCP servers,
you can think of MCP servers like XcodebeBuildMCP as "extensions" of vibe-code editors.

So we have solutions that bring the coding experience closer to Xcode, we have MCP servers that can bridge LLMs with the Xcode and app development world,
what's missing you might guess... Well quite a lot indeed, and some changes in foundational pieces in the Apple ecosystem, without which the vibe coding experience will lag behind.

## Built-in extensibility

There's a limit to how much Alex or CopilotForXcode can do and read through the accessibility API.
On one side, this is excellent for Apple because it puts them in a unique position to build a more tightly integrated experience that could redefine developer workflows,
and this is something that we know well at Tuist (wink, wink).
Apple has consistently demonstrated their ability to take emerging technologies and elevate them through thoughtful integration with their platforms. While AI development may not have been their primary focus historically, Apple's track record of transforming industries when they do decide to fully enter a space is impressive.
Imagine if instead they started layering Xcode, opening the bottom-most layers, and giving developers the tools to extend it.
Sounds familiar? That's what Microsoft did with VSCode, and what has given the explosion to editors like Windsurf, Cursor, or [Void](https://github.com/voideditor/void), and we'll most likely see more in the years to come.
Xcode's extensibility has historically been limited by design,
but there are encouraging signs that Apple recognizes the tremendous value in opening up their developer tools. With the growing importance of AI in development workflows, this year could mark a turning point where Apple embraces a more open approach to their tooling, unlocking a world of new coding possibilities for app developers.

Thanks to that, extensions like Alex or CopilotForXcode wouldn't have to rely on a high-level API like the accessibility,
they could hook into the internals of Xcode and even use their internal APIs for interacting with Xcode projects,
for example to add a source file to a target,
or to know which files are compiled as part of a target.

## Shorter feedback cycles

When doing vibe coding, there's an agent mode, where you give the interface a set of requirements,
and they go ahead and do the work for you.
This is often referred to as "agentic" AI.
This mode requires having a way for the AI to verify that the changes are valid,
similar to how you do when you hit compile or run the tests, to make sure the code compiles and does what it's supposed to do.
If those "checks" run fast,
the agent can iterate fast based on your input,
however,
if they are slow,
or even worse,
they are unreliable,
it can completely spoil the "vibe" in the coding.

Sounds familiar? This is the scenario that developers face every day in their day-to-day development,
and that motivated the creation of Tuist in the first place:
unreliable builds caused by implicit configuration, frequent deletion of derived data in the aim of making a compilation work,
one-line changes that trigger long compilations...
Many of us might have normalized all of that as inherent to building apps with Xcode.
This has led some organizations to explore alternative approaches using JavaScript runtimes. 
Attempting to vibe-code gives us a fresh perspective on developer experience and highlights opportunities for enhancing performance in ways that Apple is uniquely positioned to address.

While the current "vibe" coding experience has room for growth, Apple is already laying the groundwork for significant improvements.
Last year they introduced [explicit modules](https://developer.apple.com/documentation/xcode/building-your-project-with-explicit-module-dependencies) - a forward-thinking move that shows their awareness of what's needed for better tooling integration.
They're also working on a sophisticated [content addressable store](https://github.com/swiftlang/swift-build/tree/main/Sources/SWBCAS), 
which demonstrates Apple's commitment to building the foundation for next-generation development experiences.
So while other runtimes like the web platform,
where you can throw React or web components and see them being reloaded in seconds,
we are insanely far from enabling the same experience in Xcode.
We need to finally move on from all that implicitness that brought teams the convenience to modularize,
and introduce more explicitness and dynamism into the toolchain such that you can iterate in a small part of your apps.

Who knows... perhaps we move in the direction of [doing code-injection](https://github.com/krzysztofzablocki/Inject) escaping the compiler all together,
but once again, this is another area where language convenience, like being able to reference a symbol without the full symbol identifier, might come at the cost of once more, not being able to enable certain developer experiences.

## Runtime context

Another piece of information that will be useful as well will be runtime context.
A few weeks ago the developers behind the [Elixir programming language](https://elixir-lang.org) and the [Phoenix web framework](https://www.phoenixframework.org) introduced [Tidewave](https://tidewave.ai),
which they presented as a technology to expose runtime context from web apps to MCP-compatible code editors.

When your software is running, 
there's a lot of runtime context in it that might be useful to further enhance the vibe coding experience.
For example, imagine being able to debug your API client by sending requests through Claude and asking it to verify the responses and iterate on the code based on what they see in the responses.
These are just some examples, but you get the idea.
The more context, the better,
and runtime context can be quite useful.

In that sense,
using runtime solutions that model problem spaces very declaratively can play a key role in enhancing your vibe coding experiences.
And there's no better example than Point Free's architectural approach.
Your application state lives in a store, and the mutations that are possible are known at compilation-time, so you could trigger those mutations,
not by interacting with UI, but by chatting with an LLM. Wouldn't that be cool?
The agent could navigate the app, and who knows,
even reach user scenarios that you didn't think of and write some tests for you.
The possibilities are endless.

In that regard, we wonder if Apple will introduce an official framework that can be used by other frameworks and libraries
to have a unified way to share context with the outside world.
Ideally, they'd expose an MCP server,
but we all know Apple likes to sometimes go the proprietary path and come up with proprietary solutions.
This is a direction that sooner or later will be more deeply explored by the ecosystem.

## Better documentation and examples

LLMs are trained with existing code examples and documentation.
Therefore, the more and the better they are, the better the work that LLMs produce will be.
Unlike the web, where there are plenty of open source projects and libraries to learn from,
the number of open source projects and apps out there to learn from is quite limited.
One could argue that Apple could use their own projects,
but are they in a state where they can be used to train models?
Only Apple and their engineers know,
but that might not be the case.
So if there are not that many references out there,
this will unfortunately make LLMs not as good at writing Swift as they might be in other languages.
And the same goes for the docs.
The documentation of the frameworks and the programming language needs to be top-notch.
It needs to cover in detail what the APIs are for,
include multiple examples of how they can be used and the output that they'd produce in those cases,
and also caveats that someone should be aware of.

It almost feels as if all your past investment into great docs and examples is finally being put into practice.
The good thing is that if the LLMs are not doing a great job, you can blame someone else,
but the reality is that a lot has to do with all that data it's been trained with.
The push for vibe coding can finally be a wake up call for Apple to fill many gaps in their documentation,
ensure they provide as many examples as they can,
and expose an [llms.txt](https://llmstxt.org) endpoint that LLMs can use to improve their models.

## Explicitness, explicitness, explicitness

The more explicit the context is and the dependencies between different pieces of context,
the more likely LLMs will do a better job at their tasks.
Take for instance [this Swift evolution](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0439-trailing-comma-lists.md) proposal,
which introduced support for trailing commas in comma-separated lists.
As a language addition,
it's a great convenient improvement.
However, it's only supported from the Swift version 6.1.
In other words,
to know whether that feature can be used,
the LLM needs to know which Swift version a target in your Xcode project is compiled with,
and if this information is dynamically resolved at build time based on the build configuration and a setting in an .xcconfig file,
the chances that the LLM uses that information to use the right language features is very unlikely,
so you'll force the agent into a trial-and-error approach to coding for you,
which is slow and frustrating.

Therefore, I believe in this new world we are entering,
it's crucial that we embrace explicitness, and that we make all that information accessible to LLMs,
so the more open, the better.
Otherwise we'll fall way behind in what "vibe coding" means in the web vs Swift app development ecosystem.

## Closing words

It's early to know what vibe coding will look like in years from now,
but it's clear that it's here to stay,
and with so much creative energy and capital going to the space the concept is likely to evolve and challenge our approach to coding.
Apple's thoughtfully designed solutions and mental models have served developers well for many years,
and now they have an exciting opportunity to evolve these approaches for the LLM era, where high-quality, explicit, and accessible context becomes increasingly valuable.
We can see vibe coding as an inspiring catalyst for Apple's next leap in developer tools,
and given their history of transforming industries through careful innovation and integration,
we're optimistic about how they'll enhance their already robust software ecosystem,
potentially pioneering new approaches that align with their commitment to quality and providing developers with exceptional tools to build remarkable apps.

If this is a space that piques your interest, we recommend following the work that [Cameron](https://www.async-let.com), [Rudrank](https://academy.rudrank.com), and [Thomas](https://www.dimillian.app) are doing bridging the gap between Xcode and AI.

**_This post was written by humans with grammar and style reviewed by Claude 3.7 Sonnet._**
