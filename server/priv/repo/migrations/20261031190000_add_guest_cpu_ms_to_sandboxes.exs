defmodule Tuist.Repo.Migrations.AddGuestCpuMsToSandboxes do
  use Ecto.Migration

  # The guest CPU time a running sandbox's node last reported when it was
  # active, which tells an idle guest from a busy one.
  def change do
    alter table(:sandboxes) do
      add :guest_cpu_ms, :bigint
    end
  end
end
