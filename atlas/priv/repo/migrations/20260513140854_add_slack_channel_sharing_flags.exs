defmodule Atlas.Repo.Migrations.AddSlackChannelSharingFlags do
  use Ecto.Migration

  def change do
    alter table(:slack_channels) do
      add :is_shared, :boolean, null: false, default: false
      add :is_ext_shared, :boolean, null: false, default: false
    end
  end
end
