---
title: "MCP"
category: "vision"
tags: ["vision", "productivity", "infrastructure", "cache", "compute", "toolchain"]
excerpt: "Most companies optimize developer productivity by throwing faster machines at the problem. But productivity has three layers, and ignoring the hard ones means wasting the easy ones."
author: pepicrft
og_image_path: /marketing/images/blog/2026/03/04/three-layers-of-developer-productivity/og.jpg
---

It’s 8 am in the morning, and the alarm goes off like every morning for David. He takes a shower, makes himself a quick coffee, and rushes to take the public transport to his company’s office in the district of Kreuzberg in Friedrichshain.

The company that employs him has an app used by billions of users, and he joined the company when they were 5 people as an app developer to work on product. But things look very different today. The company has grown up to thousand employees. He transitioned to this new team that leadership necessary: the platform team. You’ll work on making your colleagues productive he was told... It sounded exciting at the time, but David had little idea what the job would entail.

As soon as he started, he became the go to person for the i-don’t-understand errors emerging in CI looks. It was fun initially but as the volume increased he started to noticed a pattern. Since it was easier to get him to context switch, their peers leaned on asking over investing energy to debug the issue. He was becoming the doctor for things are broken or slow pains. He had to learn about the intricacies of Xcode and Gradle build systems to debug and fix the most obscure issues that emerged. 

With the growth of the product organizations, things became unmanageable for him. At the same time, he couldn’t get a headcount because he hadn’t found a framework to measure the impact of his work. And leadership asking him to investigate what it’d take to move to React Native didn’t help. They’d heard from Shopify’s CEO that the’d been successful a doing that there and had a great impact.

Turns out all the knowledge he had acquired about the underlying tools were not shared, so even after introducing a tool to help with the Gradle side of things, most people didn’t see the effort to go deep into understanding it. On one side, he became an indispensable piece in the org, but putting down fires was not something he’d enjoy doing for the long run.

But this week was different. It was quiet. He arrived early to the office, left his remaining coffee on the table, turned on the computer, and with a few commands, he had Xcode and Gradle data and blobs flowing to and from Tuist. More beautiful than his previous tool, but he felt nothing would change. That feeling just lasted a few minutes until he tried something that would change his team’s culture.

![](/marketing/images/blog/2026/03/20/mcp/david.png)

## xxx

David story's is not unique. Developers becoming doctors of their product teams' projects, tools, and generated artifacts is very common. In fact, we were starting to become doctors of our customers data. They'd come to us asking for solutions to problems that were not directly related to Tuist. Helping them felt the right thing to do, but soon we realized we needed to do something if we wanted to scale this kind of support with our customers. Don't they say if you listen and oserve your customers close enough, you can learn a lot about what they need and build solutions for them. Turns out we had the best example in front of us, and we just had to click the dots.

When one thinks about what it takes to be that doctor there are two fundamental pieces:

- The data: What's happening in those workflows that developers run.
- The knowledge: What the data represents in a broader context (e.g. the build system that uses it)

Turns out the data is something that we'd been collecting at Tuist. First from Xcode builds and test runs. Later on, from Gradle build toolchain. We had built the infrastructure to persist it over time and across environments, and made it available via web-native APIs like our HTTP REST API. But what about the knowledge? That's when we realized that perhaps, LLM frontier models that people have been using would have the right amount of knowledge to understand the data that we'd expose to them, and we could extend them with additional context if needed to make them more effective at their job.

Voilá, what if we could turn LLM-based agents like Codex or Claude into a project and app health doctor by feeding it with the right data and knowledge?

Coincidentally going deep into every toolchain is not an attractive task for businesses. However, every company sooner or later has a platform team, more so in the world of agentic workflows where the need for optimizations happens earlier, so what if we could become a virtual platform team, or a copilot for platform teams.

In the past weeks we've been investing in the first pieces to enable that vision, make all the data accessible, and provide additional knowledge through skills for the common use cases that we are seeing our customers having. How to interface with that data is a user's decision, but we provide the following interfaces:

- CLI + Skills: We solved distribution of the CLI years ago, and coincidentally, CLI became trendy again because they play well with coding agents. This positioned us well, and made the CLI a great candidate to provide a read interface to projects' data. Most of our data is now exposed through CLI commands. Additionally, we've created [skills](https://docs.tuist.dev/en/guides/features/agentic-coding/skills) that you can complement the CLI commands with to make them more effective at their job.
- MCP: We've also exposed an authenticated [MCP server](https://docs.tuist.dev/en/guides/features/agentic-coding/mcp) that provides similar capabilities but using MCP primitives: prompts and tools.

You'll likely see discussions on the Internet about MCP vs CLI. We believe both have pros and cons, so we prefer to leave it in your hands to decide. If you are already using the CLI, you might be better off with the CLI, which also manages your session for you. However, we haven't really solved Skills distribution and updating as an industry, so they are a bit of a mess. On the other side, MCP setup and authentication is very convenient, and the LLM client can take care of doing the auth flow and managing the session. This makes Tuist's data accessible to higher-up roles that don't necessarily have the CLI installed. For example an executive or director of engineering coul dhave a look at flakiness data by just adding the MCP to their LLM desktop app. However, if you need to action on the data, you likely need the codebase and the CLI, so having an MCP might feel a bit redundant.

What follows are some use cases of how you might want to interface with thee capabilities using AI agents:

## Fix flaky tests

Flakiness requires analyzing test data across runs. We do so. We know which tests are flaky, and we expose that information through our read interface. What that means is that you can start your agentic coding session and tell your agents:

```txt
Can you fix the most flaky tests in this project?
```

The coding agent will use the CLI or the MCP tool to get that information, and then a skill or prompt (MCP), which provides some guidelines on how to fix the flaky tests. Long-term, we'd like to do that proactive work for you so that you get thos tests fixed automatically, but one thing at a time.

## Understand a build or a test run

When things fail, for example a build or a test suite run, developers typically go to the logs and try to understand the errors themselves. However, this can get tricky, specially if you are not very familiar with the codebase, the internals of it, or the underlying toolchain (e.g. Gradle). All the diagnostics data necessary for that is collected by Tuist through our insights feature. So all you need to do is:

```txt
Why did this build fail https://tuist.dev/tuist/tuist/builds/build-runs?
```

The coding agent can pull information from that build (e.g. warnings, build errors, tasks) and diagnose what the issue might have been. While the information for diagnosing might be in the logs, internal build data often provides additional information that helps diagnose it more effectively and providing a better set of next steps to address the issue. In practice, this means that teams don't need to go to the platform team or engineer and treat them as doctors. They can be doctors of their own work's data.

## Diagnose why a bundle size is too large

Our bundle insights feature allows teams to understand how the size is distributed across the bundle. Sometimes, the size is larger than what it should be because there are resources that are duplicated, or otpimizations that could have been applied but they did not. Through the dashboard, people can traverse the bundle structure and try to diagnose issues themselves. We do too, but there might be scenarios that we haven't codified deterministically yet. So what if agents could do that job for you?


```txt
Can I optimize anything in this bundle https://tuist.dev/tuist/tuist/bundles/019ce77a-29cf-77bb-9cfc-4f4f500c41e4?
```

Or you can also compare bundles:

```
How do these bundles compare https://tuist.dev/tuist/tuist/bundles/019ce77a-29cf-77bb-9cfc-4f4f500c41e4 and https://tuist.dev/tuist/tuist/bundles/019ce735-0efc-7288-87a5-bae99397554f?
```

The interfaces are designed such that coding agents can go as deep and broad as needed ensuring they don't exhaust the context window.

## Optimize cache usage

Something we keep repeating our customers about the cache is that part of the responsibility of making it effective is on us by ensuring low latency and high-bandwidth access to it from any environment. But the second part of it is on them, since they need to ensure their project's graph is designed in a way where tasks with side effects are non-existent, or where tasks are not a parallelization contention point. Since Tuist collects cache data from your builds, you can also use that data to optimize your cache usage:

```
Why did the cache hit rate drop here https://tuist.dev/tuist/tuist/runs/019ce7bb-fdc6-7f15-afa4-09249b083f21?
```

Noticed we didn't specify the baseline. The sills and prompts instruct the coding agent to take the project's repository main branch as the baselin to compare against, so it can tell what might have caused any issues, or even a regression in the project's configuration.

## Closing

David's role is much different today. Teams don't depend on him anymore to understand and optimize their setup. All the engineers interface with Tuist directly. His work is more fun today, and if leadership has questions, they can find answers themselves using LLM clients, for example the impact that a new version of Xcode or Gradle has had on teams' machines. He has noticed Tuist's is open source and has a public API so he's started playing with the idea of contributing integrating other workflows into the Tuist ecosystem and infrastructure so more teams at his organization can benefit from it.

At Tuist we believe are about to tap into a new paradigm to dev productivity.
This shift requires collecting the right amount of data and making it available.
Which one you might guess? The ones that help us shift us from being the ones answering to our users from being the agents the ones providing the answers to themselves. It's a continuous learning exercise, not just with our users, but with ourselves, since we use Tuist every day.
It also requires education.
We can't assume everyone is comfortable going to an agent to answer these questions. It's an investment, but I think it's worth it, and we hope once the pattern sticks, it comes with a network effect that makes more organizations plug Tuist into their workflows to be a virtual platform team.

Our long-term goal is to take a more proactive role where we know when an action needs to be taken, like fixing a flaky test or optimizing a bundle, and we do it for you. Sentry is already doing it for errors with Sheer, so we want to take that role in the productivity space. First we close the loop with the data, second, we elevate the developer experience making the experience agentic.

If this sounds interesting, you can add the [Tuist MCP](https://docs.tuist.dev/en/guides/features/agentic-coding/mcp) to your LLM app/coding agent, or install our [skills](https://docs.tuist.dev/en/guides/features/agentic-coding/skills), and start playing with it. Your feedback is extremely valuable here. You can share that in our [community forum](https://community.tuist.dev), or [Slack group](https://slack.tuist.dev). Also, if this resonated with you and wanted to have a chat with us about productivity, build toolchains, and how Tuist could have an impact in your organization, you can jump on a [call with us](https://cal.tuist.dev/pedro/tuist-consultation).
