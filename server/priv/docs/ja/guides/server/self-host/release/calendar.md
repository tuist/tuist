---
{
  "title": "リリースカレンダー",
  "titleTemplate": ":title | セルフホスティング | サーバー | ガイド | Tuist",
  "description": "TuistサーバーとKuraの最新バージョン、最近のリリース履歴、および今後の安定版リリース予定。"
}
---

# リリースカレンダー {#release-calendar}

最新のサーバーおよびKuraのバージョン、最近のリリース、今後のリリースウィンドウを確認してください。チャンネル保証、イメージの固定、バックポートポリシーについては、<.localized_link href="/guides/server/self-host/release/channels">リリースチャンネル</.localized_link>を参照してください。

安定版のプロモーションは、<.localized_link href="/cli/release/calendar">CLIリリーストレイン</.localized_link>に合わせて、月曜日の06:00 UTCにスケジュールされています。次のリリース候補は、スケジュールされたプロモーションが成功した後にのみ作成されます。障害が発生した場合、各コンポーネントは独立して遅延する可能性があり、メンテナーはスケジュール外で公開することもできます。将来のウィンドウは計画であり、約束された公開時間ではありません。

パッチリリースとバックポートは、毎週のスケジュールではなく、必要に応じて提供されます。以下の履歴では、公開されたリリースをそのノートと実際の公開日にリンクしています。

<.release_status status={@release_status} components="server,kura" />
