---
{
  "title": "About Tuist",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Extend your Apple native tooling to better apps at scale."
}
---
<script setup>
import VPFeature from "vitepress/dist/client/theme-default/components/VPFeature.vue";
</script>


# About Tuist {#about-tuist}

In the world of app development, particularly for platforms like Apple's, organizations often encounter **productivity roadblocks.** These can include sluggish compilation times, unreliable tests, and intricate automation workflows that drain resources. Traditionally, companies address these issues by forming dedicated platform teams. These specialists maintain codebase health and integrity, freeing other developers to focus on feature creation. However, this approach can be expensive and risky, as the departure of key team members can severely impact productivity.

## What {#what}

**Tuist is a toolchain designed to accelerate and enhance app development.** We integrate seamlessly with official tools and systems, meeting developers in familiar territory. By shouldering the burden of tool and system integration, we enable teams to channel their energy into feature development and improving the overall developer experience. In essence, Tuist serves as your virtual platform team. We're with you every step of the way - from the spark of an app idea to its user launch - tackling challenges as they arise.

Tuist is comprised of a [CLI](https://github.com/tuist/tuist), which is the main entry point for developers, and a <LocalizedLink href="/server/introduction/why-a-server">server</LocalizedLink> that the CLI integrates with to persist state and integrate with other publicly available services.

## Why {#why}

Why choose Tuist? Here are compelling reasons:

### Simplify 🌱 {#simplify}

As projects grow and span multiple platforms, modularization becomes crucial. Tuist streamlines this complexity, offering tools to optimize and better understand your project's structure.

**Further reading:** <LocalizedLink href="/guides/features/projects">Projects</LocalizedLink>

### Optimize workflows 🚀 {#optimize-workflows}

Leveraging project information, Tuist enhances efficiency through selective test execution and deterministic binary reuse across builds.

**Further reading:** <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink>, <LocalizedLink href="/guides/features/selective-testing">Selective testing</LocalizedLink>, <LocalizedLink href="/guides/features/registry">Registry</LocalizedLink>, and <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink>

### Foster healthy project evolution 📈 {#foster-healthy-project-evolution}

We provide insights into your project's dynamics and expert guidance for informed decision-making. This approach prevents the frustration and productivity loss associated with unhealthy projects, which can lead to developer attrition and missed business goals.

**Further reading:** <LocalizedLink href="/server/introduction/why-a-server">Server</LocalizedLink>

### Break down silos 💜 {#break-down-silos}

Unlike platform-specific ecosystems (e.g., Xcode's contained environment), Tuist offers web-centric experiences and integrates seamlessly with popular tools like Slack, Prometheus, and GitHub, enhancing cross-tool collaboration.

**Further reading:** <LocalizedLink href="/guides/features/projects">Projects</LocalizedLink>

---

If you want to know more about Tuist, the project, and the company, you can check out our [handbook](https://handbook.tuist.io/), which contains detailed information about our vision, values, and the team behind Tuist.
