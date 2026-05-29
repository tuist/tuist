---
title: "Inside Atlas: the operations platform we built for ourselves"
category: "vision"
tags: ["vision", "business", "ai", "agents", "tooling"]
excerpt: "We are a very small team, and from the beginning we have been obsessed with operating efficiently. Off-the-shelf tools made us bend our work to fit them and siloed our data. So we built Atlas, our own operations platform, leaning heavily on LLMs and agents. Here is a tour of what we have actually built into it: sales, finances, product operations, and the interfaces that tie them together."
author: pepicrft
og_image_path: /marketing/images/blog/2026/05/29/inside-atlas/og.jpg
---

Tuist is a very small company, and from the beginning we have been a little obsessed with operating in the most efficient way possible. For a while that meant outsourcing each function to a different tool or service. **It worked, until it did not.**

What kept happening is that we ended up adjusting the way we work to fit those tools. We had silos of information we could not correlate, even when the connections between them were obvious. We were paying for all of it. And sooner or later we hit the limit of what each tool could do, at which point we were stuck depending on some other company to build the feature we needed.

One day we sat down and realised something that is, frankly, obvious, and that plenty of people have realised before us. **The cost of manufacturing code has collapsed.** We had already developed the muscle to deploy our own infrastructure, with a recent move to [Kubernetes](https://kubernetes.io). We had [Noora](https://www.figma.com/community/file/1512465864777652939), our design system for [Elixir](https://elixir-lang.org). We had every piece we needed to build our own operations system. So instead of accommodating the way we work to the models that off-the-shelf tools propose, we could decide how we wanted to operate as a company, and then design the tools for that.

This is something Marek and I always admired about [Shopify](https://shopify.com). They build their own tools, on their own systems, with their own information architecture, so that the company operates the way they think it should. For a long time that felt out of reach for us. Building something like that would have taken energy we could not spare, energy that would otherwise go into building product and growing revenue. With the equation shifting, we decided to embrace the Shopify model anyway. We called the result Atlas, and it leans heavily on LLMs and the agents we build on top of them.

## Sales, where we started

The first thing we focused on was sales.

A lot of CRM tools are, when you look closely, database wrappers with a few nice features on top. So we built our own version of that wrapper. At the core, Atlas tracks our leads, prospects, and accounts, each with a state that represents where the customer is in their lifecycle, plus whatever metadata we have found useful to keep.

On top of that core, we built something that routes context. Any piece of context that happens anywhere, a Slack conversation, an email thread, finds its way to the right account. An agent captures the context, the people involved, and the state of the deal, and persists it for us. So for every customer we have not only a record of everything that is happening, which otherwise tends to be hopelessly siloed, but also a running summary of where things stand, and nudges to help deals move forward.

![An Atlas account overview showing an account's priority, lifecycle, deal stage, value, an auto-generated summary, a "why now" section with nudges, and contacts](/marketing/images/blog/2026/05/29/inside-atlas/account-overview.png)

_The data in this screenshot is fake, used only to illustrate the interface._

The nudges are the part I am most excited about. Atlas correlates a customer's profile with the work we are doing as a company. We synchronise our product development into the same place, and on a schedule an agent looks across all of it and tells us whether it might be a good moment to loop in a particular prospect or customer. Maybe we just shipped something they asked about three weeks ago. Maybe their usage pattern points to a feature they have not tried yet.

The point is that we do not remove the human from this. **I think the human is still necessary.** What we do is arm that conversation with far more context, so we get the right nudge at the right time, and the conversation is far more effective than a generic "hey, how is it going."

We see a lot of companies going the other way, automating the same templated email to everyone, and I do not think that works. The pattern we actually admire is [Grafana](https://grafana.com). They look at our usage data, and an account manager follows up with patterns they have noticed in our consumption, suggesting ways to save costs. It is genuinely nice to be reached out to with that much context behind it. We want to build something similar, without needing a person to manually stitch together data from a dozen systems. We are not there yet. But once we are, I think the way we manage both deals and accounts is going to be far better, with far less manual work. The human effort will land where it belongs, on the conversation itself, which is the part you cannot and should not replace.

## Finances

The second piece we built was finances.

We were using a tool that connected to our bank accounts and gave us a clear picture of the company's financial health. It was genuinely good. It even had an embedded agent we could ask questions, and daily and weekly pulses that would flag things like a transaction we had never seen before, or a service whose cost had crept up. Keep an eye on this, it would say.

The problem was the same problem as everywhere else. You had to use their agent, inside their product. There was no MCP interface to plug into. And the data was siloed. It had no idea which account a payment belonged to, or how a transaction related to the rest of the company. We felt this had to be connected to everything else.

So we built a finance piece into Atlas. It synchronises data from our banks through their APIs. Agents categorise the transactions, which we used to rely on an external system for, one that was never quite right, and now we can tune it exactly to our needs. Watching that happen automatically is a small joy. On top of it, we can have conversations about our finances on Slack, and we get pulses written in the tone we want, surfacing the kind of data we actually need to make decisions.

Because the dashboards are built on Noora, we can point our coding agents at patterns we already designed for the Tuist product, and they come back with dashboards that are genuinely beautiful. It does not look like a standard UI that has been vibe coded. I am proud of both the investment in the design system and the investment in Elixir as the technology for the internal web services we build.

![An Atlas finance dashboard showing a renewal scenario with ARR, monthly renewal revenue, adjusted burn, and plan-adjusted runway, a list of bank accounts with balances, and a transactions table with categorised credits and debits](/marketing/images/blog/2026/05/29/inside-atlas/finance-dashboard.png)

_The data in this screenshot is fake, used only to illustrate the interface._

## Product operations

The third area we started building is product operations. This is still early, and somewhere we want to invest a lot more. We are not claiming the way we work today, with coding harnesses and loosely enforced processes, is the finished shape. There is value in putting some structure behind it, because we tend to follow the same phases of the software lifecycle every time.

We started with what happens after a release.

We release continuously. As soon as something is merged, if the change is releasable, we use [git-cliff](https://git-cliff.org) to cut the release. Those releases usually reference issues on the PR that originally came from a customer or an account. Previously we had to remember to circle back and tell that customer the thing they asked for had shipped, and that they should update. Now that work happens automatically. When we release, Atlas can trace its way back to the issues and requests behind the change, and report that they have been addressed. That used to be a chore that needed a human, and it was easy to drop.

![An Atlas releases view listing recent CLI and server releases with their status (notified, failed, skipped, pending), referenced issues, and how many issue updates were posted](/marketing/images/blog/2026/05/29/inside-atlas/releases.png)

_The data in this screenshot is fake, used only to illustrate the interface._

From there we started looking at acting on signals. Alerts from observability platforms like Grafana. Slow queries against the database. Systems misbehaving. If we have a coding harness, and we have all the data from [Sentry](https://sentry.io) and the other platforms, we can act on that data and, ideally, produce a PR. If not a PR, then at least all the context a developer needs to start the investigation. **The moment we detect something, we should be acting on it.**

Sentry is building something in this direction, dedicated to the data they have in their own error tracking. We want something more generic, because these signals come from many different places, and we do not want to tie ourselves to any single product, because that creates a dependency on it. For us the place where everything converges is increasingly Grafana. Logs, metrics, errors, [OpenTelemetry](https://opentelemetry.io) data, all of it lands there with the full context of our systems. There is initial investment happening here, and we will share more about it soon.

## The interfaces

The rest of Atlas is about how we interact with all of this.

The obvious interface is the dashboard. But it is just as obvious that everyone now talks to technology through chat. So an [MCP](https://modelcontextprotocol.io) was a necessary piece. We have one, and all of this data is reachable from harnesses like Codex and Claude. If I want to talk about our finances, I open Claude and start chatting. There is an authorization model underneath it, because some data is not for everyone, and that is all carefully controlled.

Then we came across [Shopify's blog post](https://shopify.engineering/under-the-river), and [Tobi's post on X](https://x.com/tobi/status/2053121182044451016) about River. River is a Slack bot, a public interface where anyone in the company can see the conversations. We loved that idea, so we took inspiration from it and built our own internal bot. People can ask about a particular deal or account, or dig into the finances, right there in Slack. Everything happens in the open, and anyone can follow along with conversations other people are having at any time. There is something quietly beautiful about that, so we borrowed it.

![A Slack thread where Pedro asks the Tuist Atlas bot how the company's expenses evolved over the past three months](/marketing/images/blog/2026/05/29/inside-atlas/slack-bot.png)

## Under the hood

If you are an engineer, this is probably the part you have been waiting for, so let me pull back the curtain on how Atlas is actually built.

At the foundation sits [Condukt](https://github.com/tuist/condukt), an Elixir framework we built to be our harness layer. It is the thing that turns an LLM and a set of tools into something that can reason, act, and persist state across our systems. **The piece I am most excited about is remote execution.** Tools do not have to run in the same process, or even the same machine, as the agent that calls them. We can spawn a tool inside an environment with its own security boundary, which matters a lot when an agent is touching financial data or production systems. And because the abstraction is general, Condukt can drive not just our own tools but entire coding harnesses, like [opencode](https://opencode.ai) or [pi](https://github.com/badlogic/pi-mono), running them as just another tool the agent reaches for when it needs to write code.

On top of that sits the web layer, and this is where the work compounds. We use [Phoenix](https://www.phoenixframework.org) with [LiveView](https://hexdocs.pm/phoenix_live_view), which means we can build and test the entire web experience right in Elixir, without splitting our brains across a separate frontend stack. And we use Noora, the same design system we built for Tuist, so every dashboard inherits patterns we have already designed and refined. Our coding agents can read those existing patterns and adapt them, which is why the result looks like a product rather than something hastily assembled. The investment we made in Noora for Tuist pays off a second time inside Atlas.

For inference, we use [Fireworks AI](https://fireworks.ai) to host and expose endpoints for us. We have been running [Kimi 2.6](https://huggingface.co/moonshotai/Kimi-K2.6) for our operations, and it has been a great balance of value against cost. For the more demanding coding operations we may end up exploring other models that are better suited to that kind of task, and the nice thing about this architecture is that swapping the model underneath is a small change, not a rewrite.

All of it runs on our own Kubernetes cluster, the same one we built the muscle for while moving Tuist's infrastructure there. That is not an accident. Owning the cluster is what lets us think about scaling compute for one-off coding sessions, the kind that need to clone a repository, compile the work, run a tool, and then disappear. Each of these pieces was an investment on its own, and watching them click together into a single platform is one of the more satisfying things I have built.

## The bet

This is the beginning, and I think this is the kind of investment that is going to make the difference for us as a company. Staying as lightweight as possible, so we can maximise the value we deliver with the smallest number of people.

I know this cuts against the grain of the industry, where investment is usually routed into hires, and headcount is the story you tell investors about the bets you are making on a market. We have bets too. **We just do not want to tie those bets to resources.** With the right information system, we believe we can make much better decisions, and with the right tools in place, we can be much better at our roles. We do not need a roster of hyper-specialised functions. We need to be creative about product and business, and with the right data in front of us, we have a real shot at being good at that.

There is one place where the human is not optional, and that is sales. Sales is a human skill, a social process. By taking the rest of the burden off ourselves, we get to focus on the part where we think we add the most value, which is innovating on the product and figuring out where the business could go next.

## What is next

This has been a great investment, and we want to take it into other domains.

The first is our internal documents. The platform we use for them makes it painfully hard to find anything semantically, and we want to fix that as we start rethinking how we do product.

The second is product itself, and here our thinking has taken an interesting turn. We are not going to open source Atlas, because it is so specific to the systems and tools we use, and it is not our business to build a tool that works for everyone. Every company is different. But we have been thinking a lot about what it means to contribute to an open source project in a world of agents, and we are considering doing the entire product side of this as an open source project. A framework for how product gets done in this new world, where some pieces can be automated and others need human intervention. You will probably hear more from us about this, and you will get to use it. We want to do it in the open, so people can see how we work and how we shape product, and hopefully it inspires other companies to do the same.

The thing I love most about Tuist is that we also optimise for having fun. I think the best ideas, including the best business ideas, come from people having fun and pushing on the edges of what is possible.

If you zoom out, Atlas sits on top of investments that have been compounding for months. The muscle to scale compute for running agents in sandboxed environments. Our own framework for building agents in Elixir, so we can codify all of this easily. Each of these makes the next one cheaper, and we are genuinely excited about where it goes.

That is the company we want to build.
