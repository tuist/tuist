---
{
  "title": "发布日历",
  "titleTemplate": ":title | 自托管 | Server | 指南 | Tuist",
  "description": "Tuist server 和 Kura 的实时版本、近期发布历史以及即将到来的稳定版发布窗口。"
}
---

# 发布日历 {#release-calendar}

关注当前的 Server 和 Kura 版本、近期发布以及即将推出的发布窗口。有关渠道保证、镜像固定和回溯策略，请参阅<.localized_link href="/guides/server/self-host/release/channels">发布渠道</.localized_link>。

稳定版升级安排在每周一 06:00 UTC，与<.localized_link href="/cli/release/calendar">CLI 发布列车</.localized_link>同步进行。只有在前一次计划升级成功后，才会生成下一个候选版本。故障可能独立延迟任一组件的发布，维护者也可以在计划之外发布。未来的时间窗口是计划，而非承诺的发布时间。

补丁版本和回溯按需发布，而非按周发布。下面的历史记录将已发布的版本与其说明和实际发布日期关联起来。

<.release_status status={@release_status} components="server,kura" />
