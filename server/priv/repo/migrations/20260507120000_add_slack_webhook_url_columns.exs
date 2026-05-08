defmodule Tuist.Repo.Migrations.AddSlackWebhookUrlColumns do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :slack_webhook_url, :binary
      add :flaky_test_alerts_slack_webhook_url, :binary
    end

    alter table(:alert_rules) do
      add :slack_webhook_url, :binary
    end
  end
end
