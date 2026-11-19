---
{
  "title": "發布時程表",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "Tuist Server 與 Kura 的即時版本、近期發布歷史，以及即將推出的穩定版本視窗。"
}
---

# 版本日曆 {#release-calendar}

追蹤目前的伺服器與 Kura 版本、近期發布，以及即將到來的發布時段。如需頻道保證、映像檔鎖定與回溯移植政策，請參閱<.localized_link href="/guides/server/self-host/release/channels">發布頻道</.localized_link>。

穩定版升級排定於每週一 UTC 06:00 進行，並與<.localized_link href="/cli/release/calendar">CLI 發布列車</.localized_link>同步。只有在排定的升級成功後，才會切出下一個候選版本。失敗可能導致任一元件獨立延遲，維護者也可在排程之外發布。未來的時段僅為計畫，並非承諾的發布時間。

修補版本與回溯移植依需求發布，而非按每週排程。下方的歷史記錄將已發布的版本連結至其說明與實際發布日期。

<.release_status status={@release_status} components="server,kura" />
