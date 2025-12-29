---
{
  "title": "Tuist について",
  "titleTemplate": ":title · Guides · Tuist",
  "description": "Apple 標準の開発ツールを強化し、より大規模で優れたアプリを構築する。"
}
---
<script setup>
import VPFeature from "vitepress/dist/client/theme-default/components/VPFeature.vue";
</script>


# About Tuist {#about-tuist}

アプリ開発の世界、特に Apple のようなプラットフォームでは、組織はしばしば **生産性の問題** に直面します。これには、遅いコンパイル時間、不確実なテスト、リソースを消耗する複雑な自動化ワークフローが含まれます。 従来、企業は専任のプラットフォームチームを結成してこれらの問題に対処しています。 これらの専門家はコードベースの健全性と整合性を維持し、他の開発者が機能の開発に集中できるようにします。 しかし、このアプローチは高コストでリスクが伴う可能性があり、重要な役割を担うチームメンバーの退職が生産性に深刻な影響を及ぼすことがあります。

## What {#what}

**Tuist は、アプリ開発を加速し、強化するために設計されたツールチェーンです。** 私たちは公式ツールやシステムとシームレスに統合し、開発者が馴染みのある環境で作業できるようサポートします。 ツールやシステムの統合の負担を軽減することで、チームが機能開発と全体的な開発者体験の向上にエネルギーを注げるようにします。 要するに、Tuistはあなたのプロジェクトを支えるチームのような役割を果たします。 アプリアイディアの閃きからユーザーへのリリースまで、私たちはあなたと共に歩み、発生する課題に取り組みます。

Tuist is comprised of a [CLI](https://github.com/tuist/tuist), which is the main entry point for developers, and a <LocalizedLink href="/server/introduction/why-a-server">server</LocalizedLink> that the CLI integrates with to persist state and integrate with other publicly available services.

## Why {#why}

なぜTuistを選択するのか？ その理由は以下の通りです。

### Simplify 🌱 {#simplify}

As projects grow and span multiple platforms, modularization becomes crucial. Tuistはこの複雑さを簡素化し、プロジェクトの構造を最適化し、よりよく理解するためのツールを提供します。

**Further reading:** <LocalizedLink href="/guides/features/projects">Projects</LocalizedLink>

### Optimize workflows 🚀 {#optimize-workflows}

Leveraging project information, Tuist enhances efficiency through selective test execution and deterministic binary reuse across builds.

**Further reading:** <LocalizedLink href="/guides/features/cache">Cache</LocalizedLink>, <LocalizedLink href="/guides/features/selective-testing">Selective testing</LocalizedLink>, <LocalizedLink href="/guides/features/registry">Registry</LocalizedLink>, and <LocalizedLink href="/guides/features/previews">Previews</LocalizedLink>

### Foster healthy project evolution 📈 {#foster-healthy-project-evolution}

We provide insights into your project's dynamics and expert guidance for informed decision-making. このアプローチにより、開発者の離職やビジネスゴールの達成に失敗することに繋がる健全でないプロジェクトによるフラストレーションや生産性の低下を防ぎます。

**Further reading:** <LocalizedLink href="/server/introduction/why-a-server">Server</LocalizedLink>

### Break down silos 💜 {#break-down-silos}

Unlike platform-specific ecosystems (e.g., Xcode's contained environment), Tuist offers web-centric experiences and integrates seamlessly with popular tools like Slack, Prometheus, and GitHub, enhancing cross-tool collaboration.

**Further reading:** <LocalizedLink href="/guides/features/projects">Projects</LocalizedLink>

---

Tuist やプロジェクト、会社情報について詳しく知りたい場合は、私たちの[ハンドブック](https://handbook.tuist.io/)をご覧ください。そこには、私たちのビジョンや価値、Tuist を支えるチームに関する詳細な情報が含まれています。
