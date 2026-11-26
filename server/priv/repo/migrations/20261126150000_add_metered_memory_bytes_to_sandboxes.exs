defmodule Tuist.Repo.Migrations.AddMeteredMemoryBytesToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # The memory (Pss) a bursting Linux sandbox's VM held at its node's
      # last report, which placement charges when it is above the request.
      add :metered_memory_bytes, :bigint
    end
  end
end
