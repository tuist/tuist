---
{
  "title": "发布日历",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist CLI 实时版本、近期发布历史以及即将推出的稳定版本窗口。"
}
---

# 发布日历 {#release-calendar}

关注当前的 CLI 版本、最近的发布以及即将到来的发布窗口。如需了解渠道保证、版本锁定和回溯策略，请参阅<.localized_link href="/cli/release/channels">发布渠道</.localized_link>。

稳定版升级安排在每周一 06:00 UTC。在计划的升级成功后，下一个候选发布版本将从 `main` 分支切出，随后的金丝雀版本将移至下一个次版本。失败可能会推迟发布节奏，维护者也可以在计划之外发布。未来的时间窗口仅为计划，并非承诺的发布时间。

补丁版本和回溯按需发布，而非按周计划。下面的历史记录将已发布的版本链接到其说明和实际发布日期。

<.release_status status={@release_status} components="cli" />
