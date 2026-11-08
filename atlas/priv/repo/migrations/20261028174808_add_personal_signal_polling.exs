defmodule Atlas.Repo.Migrations.AddPersonalSignalPolling do
  use Ecto.Migration

  def change do
    alter table(:signal_sources) do
      add :poll_config, :binary
      add :poll_state, :binary
      add :poll_interval_seconds, :integer
      add :poll_next_at, :utc_datetime_usec
      add :poll_error, :text
    end

    create index(:signal_sources, [:poll_next_at], where: "enabled AND poll_config IS NOT NULL")
  end
end
