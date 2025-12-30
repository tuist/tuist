---
{
  "title": "Standards",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "Learn about Tuist's stance on adopting and embracing standards over proprietary abstractions and tools."
}
---
# Standards

To create a platform that stands the test of time, we must prioritize certain principles. One of the most important is choosing standards over proprietary abstractions and tools. This principle should guide not only [our technology choices](/engineering/technologies) but also our product design.

## The Power of Standards

Standards are widely adopted and maintained by a community. For example, consider the web platform standards like [HTML](https://en.wikipedia.org/wiki/HTML), [CSS](https://en.wikipedia.org/wiki/css), and [JavaScript](https://en.wikipedia.org/wiki/JavaScript). These standards are designed to be backward compatible and evolve without breaking existing implementations. This stability allows us to focus on building features that matter to our users rather than constantly updating to maintain compatibility with proprietary tools.

Standards also enable [portability](https://en.wikipedia.org/wiki/Software_portability), allowing users to move freely across tools and platforms without being locked in. If our users choose to stay with Tuist, it should be because they love the product, not because they are trapped by the technology. While it is rare that a standard will not meet our needs, in such cases, we should actively contribute to the standardization process to ensure it evolves to address those needs.

## Embracing Long-Term Solutions

As developers, it can be tempting to adopt the latest tools that promise to solve all our problems. While these tools may offer short-term benefits like increased productivity or a better developer experience, we must remember that Tuist is a long-term, infinite game. Eventually, standards will catch up, and if they don’t, we have the opportunity to contribute to their development. For example, [OpenAPI Spec](https://swagger.io/specification/) and its tooling have evolved to compete with [GraphQL](https://graphql.org/), demonstrating how standards can advance over time.

Sometimes, peeling back the layers of proprietary tools and abstractions reveals that the core functionality has improved significantly. In such cases, the additional layers may no longer be necessary. For instance, it’s perfectly acceptable to have a [#nobuild setup](https://world.hey.com/dhh/you-can-t-get-faster-than-no-build-7a44131c) for a web project, despite common misconceptions.

By adhering to these principles, we ensure that our platform remains robust, adaptable, and user-focused, standing the test of time in an ever-evolving technological landscape.