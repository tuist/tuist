---
title: "Tuist Server is Now Source Available"
category: "product"
tags: ["product"] 
excerpt: "We're thrilled to announce that the Tuist Server is now source available. After years of building open source tools for the mobile development community, we're taking a significant step toward greater transparency while ensuring sustainable development."
author: pepicrft
og_image_path: /marketing/images/blog/2025/07/08/server-fcl.jpg
---

At Tuist, we are huge advocates of openness. We started Tuist as an open source Xcode project generator CLI and eventually built a business around the awesome foundation we’ve been developing for more than 7 years. As part of that effort, we’ve gifted the community open source solutions like [Noora](https://github.com/tuist/noora), which was featured on [Swift’s new website](https://www.swift.org/), [XcodeProj](https://github.com/tuist/xcodeproj), which many CLI tools depend on, and [XcodeGraph](https://github.com/tuist/xcodegraph), which we extracted from our project generation CLI and made available to everyone.

Unfortunately, we couldn’t open everything in the early days of the company because we hadn’t figured out where we could capture value. This left us with an itch. We knew this would be temporary and that we’d figure out a path back to openness, so I’m thrilled to announce that the Tuist Server is now [source available](https://github.com/tuist/tuist/tree/main/server).

## Why we’re opening the source code

We love working with the community. Openness eliminates barriers and makes you more accountable, leading to a much better product. When you’re building in the open, every decision gets scrutinized, every bug gets reported, and every feature request comes with real use cases attached. If we want to build the best virtual platform team for mobile developers, this is the way.

We see building an open company as a long-term game. While closed source code combined with capital can give you an initial advantage and help you move fast in the short term, the momentum a project can build over time with its community is absolutely unbeatable. There’s no better example than Microsoft’s strategic investments in [VSCode](https://code.visualstudio.com/) and [TypeScript](https://www.typescriptlang.org/) that have fundamentally shaped how developers work today. Our role models are companies like [GitLab](https://gitlab.com), [Grafana](https://grafana.com), and [Supabase](https://supabase.com), who’ve proven that you can build sustainable businesses while staying true to open principles. We aim to take a similar role in the mobile development space.

The mobile development ecosystem desperately needs this kind of openness. For too long, we’ve been stuck with proprietary tooling that doesn’t evolve fast enough or address the real pain points developers face daily. By opening our source, we’re creating transparency around our technical decisions and making ourselves more accountable to the community we serve.

## Capturing value to fund development

But here’s the reality: you need to fund development. In other words, you need to capture some of the value you produce, or the project will eventually stagnate like so many promising open source initiatives we’ve seen over the years. I really enjoyed this talk from [Penpot](https://www.youtube.com/watch?v=gyog9RJ2jHs), where they emphasized that open source captures less value than proprietary versions, but it’s also true that the ability to produce value in open source is much higher because of the transparency and community trust it builds.

This is where many open source projects fail—they focus so much on being “free” that they forget sustainability. We’ve seen countless projects start with massive enthusiasm, only to fade away because the maintainers burned out or couldn’t afford to keep working on them. We refuse to let that happen to Tuist. Our commitment is to continue investing heavily in the development of Tuist with our full-time team, ensuring consistent progress and innovation.

So how do you capture value responsibly? Every company decides on the model that aligns best with their mission and capabilities. Some organizations prefer focusing on services, for example by offering premium support, educational material, or hosting as a service. Others prefer capturing value through product innovation, so they embrace a licensing model that allows them to draw clear lines around what’s free and what’s paid. Many successful companies do a thoughtful mix of both approaches.

At Tuist, **we realized early on that what energizes us most is building product rather than providing services.** We’re engineers at heart—we love solving complex technical problems and creating tools that make developers’ lives better. We used this self-awareness as our guiding principle to find our model.

## Finding our model

Early on, we naively suffered from the [free-rider problem](https://en.wikipedia.org/wiki/Free-rider_problem). At the time, we thought developers would naturally pay for hosting the server or use our hosted instance, but the ease of self-hosting for both us and other companies—which could potentially put Tuist at competitive risk—turned out not to be a sustainable approach. So we bought ourselves some time and space to figure out the right model by developing some pieces as closed source. We knew this would be temporary until we could better understand our customers and their willingness to pay for value.

Thanks to that strategic pause, we’re now steadily capturing part of the market and understanding our customers much better, which allows us to start reverting the closing of some components. At the same time, hosting and maintaining an instance of Tuist is becoming increasingly complex—not because we made it intentionally difficult, but because it’s the natural result of solving more sophisticated problems that our enterprise customers face. Still, this complexity alone isn’t enough motivation for many organizations to pay us for hosting. We needed to find a step in between full open source and completely closed.

The challenge was finding a model that would let us be as open as possible while still ensuring we could sustain and grow the team working on Tuist. We didn’t want to fall into the trap of either giving everything away for free (and risking project stagnation) or being so restrictive that we lost the community benefits of openness.

## Fair Core License

We then discovered [fair source licenses](https://fair.io/licenses/), which aren’t traditional open source licenses but provide a compelling middle ground. One of the largest promoters of this approach is [Sentry](https://sentry.io), and their success gave us confidence in the model. Fair licenses buy you crucial time by preventing the free ride issue while committing to defer open source by 2 years since the code has been contributed. This sounded like exactly what we needed—protection from free riding that allows us to focus on building the best product we can imagine, while creating software that will eventually be available under an OSI-approved license.

The beauty of this approach is that it aligns incentives properly. Companies that want to use Tuist Server commercially either pay us (supporting continued development) or wait two years and use it for free (by which time we’ve moved on to newer innovations). It’s a fair trade that respects both our need to capture value and the community’s expectation of eventual openness.

So today, the server has joined the [tuist/tuist](https://github.com/tuist/tuist) monorepo under the Fair Core License. Of all the fair licenses available, FCL also gives us the flexibility to place some features behind a paid license, which is crucial in our current phase where we don’t have many features that are directly monetizable yet. While the line we’ve drawn might seem strict today, our plan is to progressively lift restrictions as we develop more enterprise-focused features, until we can have distinct community and enterprise versions—or who knows, maybe infrastructure hosting is where we’ll capture most of our value, at which point we might embrace Sentry’s simpler license and offer all features as long as you don’t try to compete directly with us.

## It’s a fluid model

We see FCL as an intermediate step in our journey, not a final destination. As the project matures and the needs of our users continue to evolve, we’ll regularly reassess opportunities to revisit and relax the license terms. For example, if we develop more sophisticated enterprise features—think advanced analytics, compliance tools, or enterprise integrations—we could adjust where we draw the line between free and paid. If we discover we can capture more value from the infrastructure and hosting side, we could potentially lift the licensing restrictions entirely and focus on our cloud offering, which we’re uniquely positioned to excel at since we developed the underlying software ourselves.

And who knows—if the mobile development market grows large enough and our business model proves sustainable, we could even eliminate the deferred open sourcing requirement entirely. But this is very far into the future. The model could eventually look similar to GitLab’s successful open core approach, where there’s a clear distinction between community and enterprise features.

The key is staying flexible and responsive to what our community and customers actually need, rather than getting locked into a rigid ideological position about licensing.

## What changes for me?

I imagine many of you are wondering what this actually means for your day-to-day work with Tuist. The short answer is: probably not much. Let me break this down.

If you're a developer who loves contributing to open source projects, **the Tuist CLI and all our core tooling remains exactly as it was**—MIT licensed and completely open for contributions. You can continue submitting PRs, reporting issues, and helping shape the future of mobile development tooling without any additional friction. The server components now require a simple contributor agreement, but we've designed this process to be as straightforward as possible because we genuinely want your contributions.

For organizations evaluating Tuist, **you can run the server locally for development and testing purposes**. The source code is publicly available, you can inspect every line, and modify it for your needs. However, if you want to deploy it in your production infrastructure, you'll need to obtain a license from us to legally use it in that capacity. This licensing approach ensures we can continue investing in the platform while still maintaining transparency around our technical decisions.

If managing that infrastructure sounds overwhelming (and for many teams, it absolutely should), **our hosted service remains the easiest path forward**. We handle all the complexity while you focus on building great apps. This is where we capture value to fund continued development, and it's a model that's worked well for companies like GitHub, GitLab, and countless others in the developer tools space.

## Closing thoughts

When you make a tool part of your development stack, you're placing tremendous trust in us to support your journey, and we've always felt deeply responsible for honoring that trust with an unwavering commitment to always be there for you. We focused on building a source of revenue so our passionate team could focus on Tuist full time without worrying about sustainability. We then announced our [longevity commitment](/longevity), which legally ensures that regardless of what happens to Tuist as a company, your projects and workflows won't get disrupted. We embraced a transparent pricing model and product design that actively fought against predatory enterprise practices like "contact sales" gatekeeping or feature-limited demo products that were unfortunately becoming the norm in our space.

We’ll continue open sourcing and gifting valuable projects to the community, like XcodeProj, Noora, Rosalind, and XcodeGraph—and who knows, maybe even the server itself will be fully open source in the future as our business model continues to evolve.

Tuist aims to be your virtual platform team for building incredible apps, and we believe this ambitious goal is only possible if we become more open and collaborative, not less. The future of mobile development is too important to build behind closed doors, and we’re committed to leading by example with the resources and dedication this vision deserves.​​​​​​​​​​​​​​​​
