---
{
  "title": "發布時程",
  "titleTemplate": ":title | 自行託管 | Server | 指南 | Tuist",
  "description": "Tuist Server 與 Kura 的即時版本、近期發布紀錄，以及即將到來的穩定版發布時段。"
}
---

# 版本行事曆 {#release-calendar}

追蹤目前的伺服器與 Kura 版本、近期發布版本，以及即將到來的發布視窗。如需頻道保證、映像檔固定與回溯移植政策，請參閱<.localized_link href="/guides/server/self-host/release/channels">發布頻道</.localized_link>。

穩定版升級排定於每週一 UTC 06:00 進行，並與<.localized_link href="/cli/release/calendar">CLI 發布列車</.localized_link>同步。只有在排定的升級成功後，才會建立下一個候選發布版本。失敗可能導致任一元件獨立延遲，維護者也可能在非排定時間發布。未來的視窗僅為計畫，並非承諾的發布時間。

修補程式發布與回溯移植依需求交付，而非按每週時程。下方的歷史記錄將已發布的版本連結至其說明與實際發布日期。

<.release_status status={@release_status} components="server,kura" />
