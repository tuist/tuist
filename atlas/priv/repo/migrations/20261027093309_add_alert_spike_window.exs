defmodule Atlas.Repo.Migrations.AddAlertSpikeWindow do
  use Ecto.Migration

  def change do
    alter table(:alert_rules) do
      add :threshold_window_minutes, :integer
    end
  end
end
