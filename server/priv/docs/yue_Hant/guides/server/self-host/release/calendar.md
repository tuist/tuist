---
{
  "title": "發布日曆",
  "titleTemplate": ":title | 自行託管 | 伺服器 | 指南 | Tuist",
  "description": "即時 Tuist 伺服器同 Kura 版本、近期發布歷史，以及即將到來嘅穩定版本發布時段。"
}
---

# 版本日曆 {#release-calendar}

追蹤目前 Server 同 Kura 版本、近期發佈，以及即將到來嘅發佈窗口。如需頻道保證、映像固定同回溯政策，請參閱 <.localized_link href="/guides/server/self-host/release/channels">Release channels</.localized_link>。

穩定版升級安排喺 UTC 時間星期一 06:00，同 <.localized_link href="/cli/release/calendar">CLI release train</.localized_link> 一齊進行。下一個候選版本只會喺預定升級成功之後先至建立。如果出現失敗，兩個組件可能會各自延遲；維護者亦可以喺預定時間之外發佈。未來窗口只係計劃，唔係承諾嘅發佈時間。

修補版本同回溯會按需要發佈，而唔係每週固定排程。下面嘅歷史記錄會將已發佈版本連結到對應嘅說明同實際發佈日期。

<.release_status status={@release_status} components="server,kura" />
