---
title: "Shaping a one-stop shop for app developers"
category: "product"
tags: ["vision"]
excerpt: "We reflect on what we've learned and the vision that we have for Tuist and the role it'll play in the app development ecosystem."
author: pepicrft
---

In October 2023, after 6 years helping teams with the challenges of Xcode projects, we formed a company in Germany to allow us to work full-time in what we like the most: helping app developers build build the best apps fast.

It’s been over a year, during which we’ve worn many hats and learned a lot about what it takes to build a company. Throughout that time, we thought deeply about the future of app development, the challenges that are ahead of teams, and the shape the company and the product should take to stay relevant and elevate the experience of building apps. We love openness, more so when more teams and developers are making Tuist an indispensable tool in their toolchain, so what follows is an owed unfolding of the future that we are envisioning for Tuist. Let’s dive right in.

## From first line to lost momentum

Since the inception of mobile OSs like [iOS](https://en.wikipedia.org/wiki/IOS) or [Android](https://en.wikipedia.org/wiki/Android_(operating_system)), the ecosystems have changed a lot. They offer many capabilities and manifest as many different platforms that developers are inclined to support to reach new audiences with their products. This growth, yet exciting, present developers with various needs and challenges that take the focus from the building momentum. From slow tooling to messing up with signing, or orchestrating a release, it’s just too much what a developer needs to hold in their heads when all they just want is to get the app out there and iterate.

Organizations that can afford it, throw a platform team at the problem. Developers and teams that can’t, try to get through it by plumbing different open source tools together, a process that takes time and ongoing maintenance cost. In some cases the building momentum is so spoiled that organizations fork their native efforts by introducing a dynamic runtime like [React Native](https://reactnative.dev/)’s that brings them hot-reloading and over-the-air updates bringing them the lost momentum.

This is happening much earlier these days because of the broad set of products and platforms developers aspire to support from the early days of the project.

We believe Tuist can be that platform team—just virtual.

## Escaping locally-scoped state

Unlike other ecosystems like the web, mobile has traditionally taken a local-first approach to tooling. Tools would run in an environment and the state, if any, would be scoped to that environment, which in the case of CI would get disposed on completion. This works for some workflows, like having a script that archives and exports an app signing it, but at certain point, you need state to escape that locality. Otherwise your ability to improve your dev environment is limited. For example, how do you know if your build times are getting better or worse if you can’t track them over time? Or how do you know if you have flaky tests in your suite if you can’t track consecutive results of the same test? With local-only tooling, you can't.

Moreover, development of apps is not isolated within your Xcode environment. You most likely collaborate with your peers through tools like [GitHub](https://github.com), [Slack](https://slack.com), or [Linear](https://linear.app). Taking a more holistic approach to dev tooling makes it possible to build integrations that otherwise would not be possible, like clicking on a link that you received automatically in Slack and seeing the app launching right there. That’s when the magic starts.

When state escapes a local environment, we need to persist it in a shared space, and that naturally leads to a server and a storage solution that allows tracking the evolution of state over time and the dependencies between different pieces of state. Additionally, the server can do processing asynchronously, escaping the synchronous act of generating the state, and can interface with other services via HTTP or be interfaced. It unlocks a world of opportunities in enabling that virtual platform team that can provide you with top-notch experiences.

For many years, CI was the only server-side tooling mobile tools used. Some companies built open-source solutions that required a server too, and most recently, we are seeing more open source hapenning in the space (e.g. [Tramline](https://github.com/tramlinehq)). We think this is great news for the ecosystem.

However, placing local state behind a company’s wall also means making the company behind that server the owner of your state.
This is not necessarily an issue, but as we have seen in the past with many services,
which ended up [enshittifying](https://en.wikipedia.org/wiki/Enshittification) and doing things like changing their terms to open new revenue streams with your data,
or forcing you to abusive pricing through vendor-locking,
the server-side dev tools are not free from these practices.
In simple terms,
companies reach a ceiling in a market that gets more and more saturated,
so they try to squeeze more money out of you,
and they are willing to do anything to get it.
The product and you don't matter anymore.

At Tuist we agreed that we wanted to do things differently creating a framework that would prevent this from happening.
Let me tell you about it.

## Shifting value from software to infrastructure

Businesses consist of producing value and capturing part of that value that they produce.
In the case of companies that have proprietary software,
they try to capture as much value as they can relative to the value that they produce.
But as we all know, [software and infrastructure](https://pepicrft.me/blog/2025/03/31/software-commoditizes) commoditizes,
and we are starting to see that in the [Mobile CI](https://pepicrft.me/blog/2025/03/25/mobile-ci-is-plateauing) space,
where new players propose lower margins pushing the prices down for everyone.
This is when you start to see companies exploiting their leverage to squeeze more money out of you.
The thing is, that it doesn't need to be like that.

There's another type of company: open source companies.
Unlike closed-source companies, they can produce insanely more value than the proprietary companies because they get contributions from the community.
Think about it, if your proprietary-software company is 5 developers,
you are limited to the capacity of those 5 developers, potentially improved with AI technologies and agents.
You get it.
Compare that to a world of developers that might go the extra mile to contribute to the project because they believe in the mission.
Not only this is good from the perspective of the ability to produce more value,
but also the diversity of ideas that are coming to the project.
If your 5 developers are based in some country,
then your vision of the world will be very limited to the vision of the world from that country.
Now, if you are getting contributions from many countries, it opens your perspective of the world.
This morning I was listening to [this podcast](https://podcasts.apple.com/cz/podcast/react-native-radio/id1058647602?i=1000702255560) with [Pratul Kalia](https://www.tramline.app/blog-author/pratul-kalia) about [Tramline](https://www.tramline.app/) and it made me realize how myopic we might be regarding what's happening in the world. In particular, he talks about the lag between India and the US, and how the focus on mobile took a bit more years to arrive to India.
In the case of Tuist, we are working a lot lately with communities in Japan and South Korea, which is introducing us to a world of ideas and opportunities that will lead to a much better product.

**Open source companies capture way less value, often none, but since the value that they produce is much more**, the net is higher than their proprietary counterparts.
Open source companies play more of a long-term game, and not only address building a better product, who doesn't want that, but also minimizes the risk of enshittification.

If you open your software and permissively license it, 
decisions are made in public with the community.
Any decision that would go against the values of the project or the community will be met with resistance.
And if those decisions happen,
like we've seen with projects like [Terraform](https://www.terraform.io/),
the community quickly gathers, forks the project, and continues [its development](https://opentofu.org/) in the same spirit.

If we are building a virtual platform team, a one-stop shop for app developers, it must be open source.
There's no other way, but that requires us to shift the capturing the value from the software itself, from somewhere else.

## Shifting capturing of value from software to infrastructure

Most of the value that we are capturing these days is through the software itself.
Hence why part of our software is not open source.
If we open sourced everything, we wouldn't be able to capture any value and therefore the company and the project would die, which is not something we want.
So we need to draw a line somewhere.
We are still figuring out what the right place is, but we believe it'll be a mix of infrastructure,
or in other words you pay us for a service that's fast, reliable, and available every day of the year, and we scale it based on your usage,
and features that are tailored to the needs of large enterprises,
which are usually the ones that can afford to pay for them.

As we add more capabilities to the platform, something which I'll talk about soon, hosting Tuist will become more complex.
We won't make it complex intentionally, because it'll be unnecessarily complex for us too,
but there'll be complexity that will get in the way, and that we'll develop a muscle to manage it at low-cost.
Think of [Supabase](https://supabase.com/). At the core there's a [Postgres](https://www.postgresql.org/) database. 
But many companies, including us, pay them for hosting and scaling the database because what we want is building products,
not managing and scaling databases.
Think of Tuist the same way,
**you'll want to be building your apps, not managing a service that helps you streamline the process.**
And here's another thing, because it builds on an open source commodity,
you can't go the path of abusive pricing, so prices will naturally be more fair than any other proprietary solution.

And what about everyone else that will host it for free?
That's great news for us. We don't expect them to contribute capital.
Financial capital is not the only form of capital.
They'll contribute ideas, bugs, fixes, and share the word out there.
They'll act as a marketing machine and help the product better every day.
It's another form of capital.

When will that happen? When we've shifted enough value capturing to infrastructure such that organizations are willing to pay for it.

Alright...we need a server to further streamline development, a server brings a world of opportunities for developer experiences, and we are going to bet on openness to build a reliable piece of software that companies can safely build upon. Let's talk about the product itself and how we see developer experience getting better.

## Product



Our north star developer experience for Tuist is that **you'll be able to plug your account on Tuist with a repository in your organization, and that's it.** We'll come with sensible overridable defaults such that you don't have to do any configuration work most of the time. This is something that [BuddyBuild](https://techcrunch.com/2018/01/02/apple-buys-app-development-service-buddybuild/) pioneered at the time when they proposed that pipeline YAMLs could be optional.
**They must be.**

Over the years we've developed extensive knowledge over Xcode projects, so I strongly believe we are well positioned to build a zero-configuration developer experience. Moreover, we are going to take the idea a bit further, and we are going to make workflows triggerable through the UI. As you might have noticed, most of the workflows on mobile are CI-centric. There's a reason for that, virtualizing workflows remotely is costly, so costly that only CI companies have access to that, but we plan to change that. A developer should be able to create a new preview from any commit by just clicking a button, and once again, there should be no pipeline for that. We should be able to leverage the same capability to sign the apps for the users generating the right certificates and profiles for that. We'll sign on the fly. Signing will be an implementation detail that they won't have to think about anymore.

And because we'll invest in reducing the cost of virtualization, we believe it's time to reduce the indirection between Git forges (e.g. GitHub and GitLab). We'll provide cheap runners so that you don't have to move away from GitHub Actions or GitLab CI. And if you bring your [AWS](https://aws.amazon.com/) or [Scaleway](https://www.scaleway.com/en/) account, we orchestrate the provisioning so that their cost is tied to your cost account. And obviously, if you want, we'll provide those runners.

We'll look at app development more holistically. First broadening the phases of app development that we help teams with, including project creation, and app releasing. And why not, very far into the future we might integrate with analytics and error tracking platforms to help you have an insight into how your app is performing. We are building the infrastructure for that. 

Then, we'll extend to other app ecosystems, like Android. **The problems that we are solving are not specific to one ecosystem.** The solutions might be, but we are putting a strong focus on ensuring the design is not that strongly coupled to the Apple platform. We are doing so because organizations have shared that they'd prefer to have _one-tool-to-rule-them-all_, and we believe we are very well positioned to deliver on that. And I believe that our bet on open source plays nicely with this idea because we can collaborate on bringing Tuist to new ecosystems. It'll require a good amount of social capital investment to make that happen, but once we get the ball rolling, we can plug the Tuist server into any app ecosystem.

**We'll continue maintaining the solution that gave birth to Tuist, project generation**, a feature many of our developers use and love, and upon which we can deliver optimizations such as caching, but we hope Apple gets those problems fixed at a lower level, which means we can plug directly into the foundations and add a layer of useful optimizations and utilities.

Open source won't be our unique strength. We are doubling down on our design.
Many developer tools treat design as an afterthought. We are making it core and center.
Tuist needs to feel like an enticing product that you want to have in your toolchain.
Not only that, but we are building a design system such that when we open source the server,
developers can use our pre-made components and design file to design their own features and contribute them to our server codebase.
In other words, we are designing Tuist in a way where we take more of a steering role, providing guidance, and ensuring the building blocks are well-designed to enable collaboration and contribution.

We'll also double down on [telemetry](https://en.wikipedia.org/wiki/Telemetry), something that's not common in the app ecosystem.
Apps and processes can't be optimized without data.
First, we are going to build open source tools to help with data collection.
Second we are going to standardize them and make it available from a server through an [API](https://tuist.dev/api/docs).
You can consume it from a Prometheus backend, or build your own client.
There'll be a well-documented and productized API for you to use.
And we'll provide a UI that will make the data actionable helping you make decisions,
in some cases make decisions for you,
and provide the information in a data such that you can use it to contextualize your conversations with LLM technologies.

## We are building the public infrastructure for productive app development

As more developers embark on the journey of building apps—whether as entrepreneurs or as part of the companies they join—it's increasingly important that the tools they rely on are accessible and part of a shared commons that can be collaboratively developed.

This belief is what drives us every day at Tuist. We’re not here to build private clubs for the few—we’re here to create public parks for the many.

Openness and open source are foundational to realizing that vision. We approach openness with curiosity and conviction, seeing it as the most powerful lever for building the toolchain we believe the app development world needs.

We see a clear need for a one-stop shop for app development. Just as dashboards have [Grafana](https://grafana.com/), metrics have [Prometheus](https://prometheus.io/), and Postgres has [Supabase](https://supabase.com/), **app development will have Tuist.**

We’re not in a rush. We have the resources and the long-term commitment to make this vision real. And we're on the right path.
