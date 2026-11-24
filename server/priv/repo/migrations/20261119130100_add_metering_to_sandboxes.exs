defmodule Tuist.Repo.Migrations.AddMeteringToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # The VM's CPU time and the time of the last report that metered a
      # running sandbox; NULL until its first report after it started.
      add :metered_cpu_ms, :bigint
      add :metered_at, :utc_datetime_usec
    end
  end
end
