defmodule Tuist.Repo.Migrations.AddMeteredMemoryBytesToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # The memory (Pss) a bursting Linux sandbox's VM held at its node's
      # last report, which placement charges when it is above the request.
      # `add_if_not_exists`: staging ran this as version 20261126150000.
      add_if_not_exists :metered_memory_bytes, :bigint
    end
  end
end
