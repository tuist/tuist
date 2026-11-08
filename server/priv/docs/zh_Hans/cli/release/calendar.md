---
{
  "title": "发布日历",
  "titleTemplate": ":title · CLI · Tuist",
  "description": "Tuist CLI 实时版本、近期发布历史以及即将推出的稳定版本窗口。"
}
---

# 发布日历 {#release-calendar}

关注当前的 CLI 版本、近期发布以及即将发布的窗口。有关渠道保证、版本锁定和回溯策略，请参阅<.localized_link href="/cli/release/channels">发布渠道</.localized_link>。

稳定版升级安排在每周一 06:00 UTC。在成功的计划升级后，下一个候选发布版本将从 `main` 分支切出，后续的 Canary 版本将移至下一个次要版本。失败可能会延迟发布节奏，维护者也可以在计划之外发布。未来的时间窗口是计划，而非承诺的发布时间。

补丁版本和回溯按需发布，而非按周计划发布。下方的历史记录将已发布的版本与其发布说明和实际发布日期关联起来。

<.release_status status={@release_status} components="cli" />
