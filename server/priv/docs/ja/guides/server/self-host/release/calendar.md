---
{
  "title": "リリースカレンダー",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "TuistサーバーとKuraの最新バージョン、最近のリリース履歴、および今後の安定版リリースウィンドウ。"
}
---

# リリースカレンダー {#release-calendar}

現在のサーバーおよびKuraのバージョン、最近のリリース、今後のリリースウィンドウを確認できます。チャネルの保証、イメージの固定、バックポートポリシーについては、<.localized_link href="/guides/server/self-host/release/channels">リリースチャネル</.localized_link>を参照してください。

安定版のプロモーションは、<.localized_link href="/cli/release/calendar">CLIリリーストレイン</.localized_link>と合わせて、毎週月曜日の06:00 UTCにスケジュールされています。次のリリース候補は、スケジュールされたプロモーションが成功した後にのみ作成されます。障害が発生した場合、各コンポーネントは独立して遅延する可能性があり、メンテナーはスケジュール外で公開することができます。将来のウィンドウは計画であり、約束された公開時間ではありません。

パッチリリースとバックポートは、毎週のスケジュールではなく、オンデマンドで提供されます。以下の履歴では、公開されたリリースをそのノートおよび実際の公開日時にリンクしています。

<.release_status status={@release_status} components="server,kura" />
