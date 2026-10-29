defmodule Atlas.Repo.Migrations.AddSlackAlertChannelToProjects do
  use Ecto.Migration

  def change do
    alter table(:projects) do
      add :slack_alert_channel, :string
    end
  end
end
