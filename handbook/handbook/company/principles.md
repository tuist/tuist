---
{
  "title": "Principles",
  "titleTemplate": ":title | Company | Tuist Handbook",
  "mission": "An organization is driven by its people and culture. What follows are the principles of Tuist, which together describe the foundational characteristics of the company."
}
---
# Principles

The heart of Tuist lies in its community and shared ethos. Below, you'll find the core principles that define Tuist's essence and guide our collective journey. These principles serve as our compass, helping us navigate decisions and fostering a unified approach to our work. By embracing these shared values, we ensure that our actions and choices consistently align with Tuist's vision and mission.

## Optimize for happiness

We believe happiness is fundamental to user engagement and satisfaction. In every development decision, we ask: *"Does this spark joy for our users?"*

This principle guides us to seek new perspectives, gather emotional feedback, eliminate complexity, and imagine innovative solutions. While challenging, this approach leads to products users truly love.

Inspired by user-centric philosophies like [Apple](https://apple.com)'s and [Ruby on Rails](https://rubyonrails.org/doctrine)', we strive to infuse happiness into all aspects of our work. In an increasingly complex world, we use happiness as a key metric for decision-making and feature evaluation.

By prioritizing joy in our designs, we create experiences that resonate deeply with users, setting our products apart in the marketplace.

> [!NOTE] EXAMPLES
> - A Swift DSL to declare projects
> - Optimized Xcode projects that compile faster

## By humans for humans

We firmly believe that technology should enhance and empower human potential, not constrain or replace it. Humans, with our complex emotions and diverse perspectives, can unlock technology's full potential when given the right tools and environment.

Our exceptional foundation was built by embracing this principle early on, empowering creative minds to contribute their unique viewpoints. We're confident that app builders who adopt this approach will create more human-centric, impactful applications.

Implementing this principle, especially in developer tools, can be challenging. It's tempting to focus solely on technical solutions, forgetting the human element. Remember: *computers are means to an end, not the end itself.*

To truly embody this principle, shift your perspective from solutions to needs and problems. Explore the motivations behind requests - they reveal human stories. Don't just build what's asked; understand why it's needed. Cultivate empathy and understanding for users and their challenges.

This principle extends beyond our products to our work culture. We treat each other with respect, empathy, and understanding. We foster an environment where individuals can be authentic, grow, and find fulfillment. We acknowledge that we're human and may fall short. If you see us straying from this principle, speak up. We're committed to learning and growing together, embracing our humanity in the process.

By keeping humans at the center of our technological endeavors, we create more meaningful, effective, and ethical solutions.

> [!NOTE] EXAMPLES
> - Problem and motivation-oriented focus in conversations with developers
> - Mindful support for the community

## Make simple things easy, and everything else possible

It's crucial to recognize that we can't create a one-size-fits-all solution. The diversity of cultures and needs is vast, and we should embrace this variety rather than forcing everyone into a single mold. Many projects fall into this trap, and we must avoid it at all costs.

So, what does this mean in practice? We need to pinpoint the common denominator of the problems we're addressing and build the simplest solution that resolves them. These solutions should be designed with extensibility in mind. By making them extensible, we provide an API for developers, enabling them to tailor the solution to their specific needs.

It's important to understand that identifying core elements and spotting opportunities for extensibility is a process that takes time, experience, and continuous feedback from the community. It's an ongoing balance—a constant back-and-forth between refining the simple solution, challenging the core models, and making those models more powerful and adaptable.

> [!NOTE] EXAMPLES
> - Providing documented REST API to build their own clients
> - Allowing users to declare their own resource synthesizers
> - Supporting codifying their conventions around where sources and resources are located

## Meet crafters where they are

Crafters are the people who build things.
Each crafter is different.
They come from diverse backgrounds, with varying levels of experience, needs, and preferences—whether technical or not.
We should build technology that acknowledges these differences and brings us closer to them, rather than creating a rigid model and expecting them to meet us where it's most convenient for us.

Some organizations prefer the latter approach because the former can be costly.
It requires building flexible models that serve as a foundation to accommodate the diverse needs of the community.
However, when done right, this approach fosters a unique and lasting connection with the community, helping you shape and grow your product over time.

So, when making decisions, consider whether we can get as close as possible to the community, somewhere between asking them to meet us where it's most convenient and meeting them where it's most convenient for them.
While it may not always be possible to get as close as we’d like, we should always strive to do so.

> [!NOTE] EXAMPLES
> - Using Swift as a language for our DSL
> - Localizing our documentation in multiple languages
> - Adopting `Package.swift` as the interface to declare dependencies

## Default to open

Openness is an invitation to collaboration and diversity.
We believe the best technological solutions are shaped in the open. However, many companies shy away from this approach due to fears of jeopardizing business or rapid growth.

We want to do things differently. Our goal is to build the best and most diverse solution first, allowing the business to follow a community-driven craft. Therefore, we default to openness in everything we do, only keeping private information that is sensitive or poses a significant risk to the company's sustainability, especially during our early days.

In terms of software, our approach aligns with this principle. We commoditize client-side software, such as XcodeProj and our generation logic and graph, using permissive licenses. At the same time, we treat the server as a monetization layer, offering advanced features that leverage server capabilities like databases or the ability to interact with other services.

> [!NOTE] EXAMPLES
> - Open-source CLI and components like XcodeProj
> - Open handbook
> - Open [dashboard](https://tuist.grafana.net/public-dashboards/1f85f1c3895e48febd02cc7350ade2d9)

## Community first

Tuist is where it is today thanks to its thriving community of crafters who connect with our vision and support us in advancing our mission.
Building a community takes time, and despite what many companies believe, we don't think it can be bought with money.
Tuist's community is one of our unique assets, and we must continue to nurture it.

The Tuist community is also our best marketing. Tuist spread thanks to word of mouth—people tried it, liked what they saw, and shared it with others. It’s the most authentic and effective form of marketing we can have.

Therefore, we should focus on how to continue growing our community and introduce new ways for members to connect with the project—such as through contributions, sharing their work on marketplaces, or becoming owners of some project assets. Community investment is a long-term strategy, and we must keep investing in it.

> [!NOTE] EXAMPLES
> - Gift community members with free Tuist subscriptions or swag
> - Recognize their work publicly
> - Guide them to land their first contributions