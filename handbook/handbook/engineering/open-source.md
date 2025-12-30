---
{
  "title": "Open Source",
  "titleTemplate": ":title | Engineering | Tuist Handbook",
  "description": "Open source is a powerful force that drives innovation and collaboration. At Tuist, we are committed to building a world-class open source productivity platform for app developers."
}
---
# Open Soure

Throughout history, [open source](https://en.wikipedia.org/wiki/Open_source) has demonstrated its incredible power in creating enduring software. It unites a diverse community of dedicated crafters, driven by a passion to make a meaningful impact on the world. **The value of open source often transcends financial metrics**, though it has proven to be a catalyst for thriving business markets. For instance, [Linux](https://en.wikipedia.org/wiki/Open_source) became a cornerstone of the modern Internet, showcasing the profound influence of open source. Companies like [Apple](https://opensource.apple.com/) and [Microsoft](https://opensource.microsoft.com/) were slow to recognize this, and many still hesitate, fearing the exposure of their innovations to the public.

At our core, **we believe open source is unparalleled, and it is deeply embedded in our DNA.** Rather than fearing it, we embrace open source with curiosity and a fervent desire to collaborate with fellow innovators. Our mission is to build new infrastructure that unlocks fresh market opportunities. We don't see ourselves in competition with others; instead, we innovate and share our creations, encouraging others to innovate within our space as well. This approach fosters a richer world where new ideas and markets can flourish. We aim to inspire others to join us on this path.

With this vision, we are committed to making Tuist entirely open source, following the examples of [Supabase](https://supabase.com/) and [GitLab](https://gitlab.com). Initially, we closed parts of our code out of fear of being outcompeted by VC-funded entities. However, now that our business is secure, we are reversing that decision. Our goal is to **develop a world-class open source productivity platform for app developers.**

## Best practices

Open source software has the potential to drive innovation and collaboration, but it must be approached thoughtfully. Here are some guidelines to ensure that open sourcing software is both effective and meaningful:

- Avoid open sourcing software that is not actively maintained merely for marketing purposes. Without proper maintenance, the software cannot serve its community effectively. The only exception to this rule is software that represents examples or experiments.
- Do not open source software that lacks standalone value or fails to attract interest for further development. Ensuring that the software has a clear, independent utility is crucial for community engagement and contribution.

By following these best practices, we can foster a more robust and sustainable open source ecosystem.

## Licenses

Choosing the right license is crucial to maintaining financial sustainability in open source. Here are our guidelines for selecting licenses:

- For command line tools, libraries, or packages intended for others to extend and build upon, we will use the permissive [MIT license](https://opensource.org/license/mit). Examples include the [Tuist CLI](https://github.com/tuist/tuist) and the [XcodeProj](https://github.com/tuist/xcodeproj) package.
- For projects that are integral to Tuist’s financial sustainability, we will release them under the [AGPL3 license](https://www.gnu.org/licenses/agpl-3.0.en.html), with some enterprise-specific features available under a commercial license. This ensures the project remains open while securing necessary funding for ongoing development. If there is any uncertainty about a project's business criticality, we encourage discussion in the #oss channel.

> [!NOTE] OSI LICENSES
> To ease understanding and compliance, we will use licenses approved by the [Open Source Initiative](https://opensource.org/). We will also ensure that all dependencies are compatible with our chosen licenses.

## Nice citizens of the open source world

When selecting services to meet various business needs, we should prioritize open source solutions and actively contribute to their growth. This can be achieved by reporting ideas and bugs, fixing issues, implementing new features, and supporting maintainers or companies through donations or paid hosted services. To ensure that open source projects thrive, we must be good citizens and support others who share our commitment to open source.