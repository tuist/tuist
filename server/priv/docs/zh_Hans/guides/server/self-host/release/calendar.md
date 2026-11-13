---
{
  "title": "发布日历",
  "titleTemplate": ":title | 自托管 | Server | 指南 | Tuist",
  "description": "Tuist Server 和 Kura 的实时版本、近期发布历史以及即将发布的稳定版本窗口。"
}
---

# 发布日历 {#release-calendar}

关注当前的 Server 和 Kura 版本、近期发布以及即将发布的窗口。有关渠道保证、镜像固定和回溯策略，请参阅<.localized_link href="/guides/server/self-host/release/channels">发布渠道</.localized_link>。

稳定版升级安排在每周一 06:00 UTC，与<.localized_link href="/cli/release/calendar">CLI 发布列车</.localized_link>同步。只有在计划内的升级成功后，才会切出下一个候选发布版本。失败可能会独立延迟任一组件，维护者也可以在计划外发布。未来的窗口是计划，而非承诺的发布时间。

补丁版本和回溯按需发布，而非按周计划。下面的历史记录将已发布的版本链接到其说明和实际发布日期。

<.release_status status={@release_status} components="server,kura" />
