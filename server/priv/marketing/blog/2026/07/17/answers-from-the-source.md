---
title: "Answers from the source"
category: "vision"
tags: ["vision", "support", "ai", "agents", "business"]
excerpt: "Our fast, technical support is the thing customers love and the thing that doesn't scale. So instead of scaling the support team, we packaged the way we find answers into our MCP and let people's own agents do it."
author: pepicrft
---

Support is one of the things we've worried about scaling the most, and not because it's going badly but because it's going well, which is exactly the problem. We answer fast, the answers are technical, and they come from the people who actually wrote the code. A prospect told us recently why that mattered to them, and the way they put it was that everywhere else they go there's a support team sitting in front of the product, and you can tell within a message or two that the person on the other side has never opened the codebase, whereas with us it's the opposite, and they love it for that.

The trouble shows up the moment you multiply it, because what's lovely for one customer falls apart across fifty, and the product keeps getting broader, so at some point even we can't keep all of it in our heads. Something had to give, and we really didn't want the thing that gave to be the part people liked.

## We were already doing it by hand

What we'd started doing, quietly, was reaching for a coding agent ourselves whenever a question came in that we couldn't answer off the top of our heads, pointing it at the codebase, letting it dig around, reading what it found, and relaying the answer. It worked fine, but it nagged at us, because there was nothing in that loop we were running that our users couldn't have run themselves. They have [Claude Code](https://claude.com/claude-code) or [Codex](https://openai.com/codex) open all day too, the codebase is public, and the models are the same ones they already pay for, so the only thing they didn't have was our sense of where to look, and the habit of looking there instead of opening a ticket.

So we flipped the question around, and instead of fetching the answer and handing it over, we started asking what it would take to just point people at it. Half the time it's already sitting in the docs and it's simply faster to ask us, but the other half it isn't written down anywhere except the code, and that's the case that got us thinking, because if an agent can read the sources it can check what the code actually does today rather than what we wrote about it eight months ago, and it can even go back and double-check itself before it answers. Documentation drifts in a way the source never does.

And this is something we get to do only because our source is available for anyone to read, because if you're sitting on a fully closed codebase you can wire this up for your own team, an agent reading your own sources to answer your own people, but you can't turn it around and offer it to the world the way we can, and we're pretty happy about which side of that line we landed on.

## It's all in the packaging

The whole thing comes down to how it's packaged. Telling someone to clone our repo, explain to their agent where everything lives, and rebuild the way we go find answers is never going to happen. Nobody does homework to open a support ticket. But we already run an [MCP](https://modelcontextprotocol.io) server on our own origin, and that's the thing agents connect to. So the real question was whether we could fold the entire way-we-answer-questions into that endpoint and have it just work, with zero setup on the user's side.

One half of it is search. Our docs site search runs on [Typesense](https://typesense.org), which we host and keep indexing continuously. We widened that index past the docs so it now covers our GitHub issues and community forum threads as well, next to the reference and the release notes. That matters a lot for support, because so many questions aren't really "how does this work." They're "is this a known bug," and that answer lives in an issue. And then "okay, is it fixed, which version," and that one lives in a release. All of it is one [`search_tuist`](https://github.com/tuist/tuist/blob/main/server/lib/tuist/mcp/components/tools/search_tuist.ex) call away now, and you can narrow it to a single source when you already know where to look.

## And then the source itself

Search hands you the words and the links, and the source is the other half of it. We wrote a small service that the MCP talks to, and it does almost nothing on purpose, in that it lists files, greps text, and reads a bounded range of lines out of one pinned revision of the public repo, and that's the whole surface, with no model inside it, no way to run a command, and every operation capped on time, traversal, bytes, and output. Those caps are baked into the binary rather than pulled from a config file, so nobody can loosen them by accident from a deployment, and if the service ever has to cut a result short it says so, with everything it returns linked back to the exact revision it read.

Sitting on top of that are three tools that behave like what an agent already does against a checkout on your laptop, where [`search_tuist_code`](https://github.com/tuist/tuist/blob/main/server/lib/tuist/mcp/components/tools/codebase_tools.ex#L139) finds an identifier or a config key or a command name or an error string, [`list_tuist_files`](https://github.com/tuist/tuist/blob/main/server/lib/tuist/mcp/components/tools/codebase_tools.ex#L207) pokes around a subsystem or the tests near it when you don't know the path yet, and [`read_tuist_file`](https://github.com/tuist/tuist/blob/main/server/lib/tuist/mcp/components/tools/codebase_tools.ex#L258) pulls the small slice you care about once you've found it. If you've watched an agent work through a codebase none of this is new to you, and the only difference is that it's aimed at answering a question instead of shipping a fix, running against our source right next to our server, with nothing to clone.

We stitched it together with a prompt, [`ask_tuist`](https://github.com/tuist/tuist/blob/main/server/lib/tuist/mcp/components/prompts/ask_tuist.ex), and with a set of instructions the server hands compatible clients the moment they connect, so a normal Tuist question flows through the docs and into the source before the agent ever falls back to a local file or a web search, which means you can just ask, and it grabs the vocabulary from the public material, drops into the implementation and the tests when the answer hinges on a default or a feature gate or some error path, trusts the code over the docs when they disagree, and shows you what it read, revision and all.

## What it looks like

It's easier to see than to describe, so connect your agent to `https://tuist.dev/mcp` and ask it something you'd normally have opened a ticket for, like how selective testing actually decides what to skip. The agent runs the loop above, and instead of paraphrasing a docs page it comes back with something like this:

> **How does Tuist solve selective testing?**
>
> Selective testing speeds up `tuist test` by running only the tests affected by what changed since the last successful run, and skipping the rest. It's on by default, and the mechanism is content hashing plus a server-side record of which hashes have already passed.
>
> Tuist walks the dependency graph and hashes each unit-test target together with its transitive dependencies, so any change to a target, or to anything it depends on, changes its hash ([`SelectiveTestingGraphHasher`](https://github.com/tuist/tuist/blob/b06ef5736f2806075c1c8f3209f4e1b1add4f706/cli/Sources/TuistKit/Commands/XcodeBuild/XcodeBuildCommand.swift#L162-L179)). It then pulls the hashes that passed on earlier runs, skips the targets whose hash is already in that set, and runs the rest. A hash is only recorded as passing after a green run ([`SelectiveTestingService`](https://github.com/tuist/tuist/blob/b06ef5736f2806075c1c8f3209f4e1b1add4f706/cli/Sources/TuistKit/Commands/XcodeBuild/XcodeBuildCommand.swift#L100-L115)), so a target is skippable only if it already passed at that exact hash. This hasher leaves UI tests out because they depend on the device they run on, and the generated-project flow picks them up once you hand it a destination.

Every one of those links points at a pinned commit rather than `main`, so they still say the same thing when you click them next month, and that filter, the reason UI tests sit outside this particular path, is something the agent only knows because it read the hasher and saw the comment sitting right next to it. That's the whole point of doing it this way, that the answer isn't a summary of what we wrote down but what the code actually does today.

There's a side effect to answering this way that we've grown fond of, which is that you don't just get the verdict, you get walked through the machinery that produces it, the hasher and the filter and the record of what passed, so you come away understanding how selective testing works and not only what it did. Most tools treat that machinery as the secret sauce and keep it behind a wall, and here the very thing that answers your question is the thing that shows you how Tuist is built, so every support question doubles as a small lesson in what actually makes it possible for anyone curious enough to follow the links.

The support questions look different but they land in the same place, where someone hits a bug, tracks down the fix in a pull request, and wants to know whether they can already pull it, which used to mean us digging through releases and now just means asking the agent:

> **When and where was [#11872](https://github.com/tuist/tuist/pull/11872) released?**
>
> It shipped in **CLI 4.202.4**, published 2026-07-16, as a backport onto the `4.202.x` line ([#11880](https://github.com/tuist/tuist/pull/11880)). The same fix is already on `main` for the upcoming 4.203.0, currently in its canary line.

That's a question that used to land in our inbox, answered before it ever reached us, by searching across our releases and pull requests the same way we would have.

And some questions are really just am I the only one hitting this, which is where the community threads earn their place, because someone runs into selective testing quietly re-running the whole suite on CI even though it behaves locally, and instead of waiting on us they can ask whether it has come up before:

> **Has anyone reported selective testing re-running every test on CI when it works locally?**
>
> Yes, this has been raised. There's a community thread, [Tuist selective testing is not working in GitHub action](https://community.tuist.dev/t/tuist-selective-testing-is-not-working-in-github-action/959), where someone describes the same thing, selective tests behaving locally but running the full suite in CI, which is where the discussion of why that happens is already playing out.

So rather than us fielding it a second time, the agent drops them straight into the thread where it is already being worked through, and if it turns out there is no answer there yet, that is a signal for us worth paying attention to.

## Keeping it honest

We're not walking away from support with any of this, we're changing where it happens, so instead of a question landing in our inbox it gets answered off the same sources we'd have opened anyway, through the agent the person already lives in. It scales the part of support that used to need another human on the team, and it does it far more cheaply than putting that human between the product and the people using it.

What it doesn't do is come for free, and the part we're still working out is what it quietly demands of us in return, because the moment agents are the ones answering, we have to be the ones watching how they answer. That's pushing us to invest a lot more in observability inside the MCP server than we would have otherwise. Every time the agent has to reach past the docs and into the source to get something right, that's a small signal that our documentation has drifted from what the code actually does, and if we're instrumented well enough to catch it we can go fix the docs instead of hearing about the gap months later from someone who got bitten by it. The same system that answers the question ends up telling us which answers we should have written down already, which is a nicer problem to have than the silence we used to get.

And the honest reason any of it works is that our source is available for anyone to read, which is a big part of why we can do this and most companies in our shoes can't. If your source is fully closed this particular door is shut, and that's a shame, but if it's public, or even just readable by the people you support, it's worth asking what it could answer if you packaged it the way an agent actually wants to read it.
