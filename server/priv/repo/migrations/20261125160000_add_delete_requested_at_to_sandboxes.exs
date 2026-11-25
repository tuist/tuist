defmodule Tuist.Repo.Migrations.AddDeleteRequestedAtToSandboxes do
  use Ecto.Migration

  def change do
    alter table(:sandboxes) do
      # When a delete was asked for. A delete whose node call fails keeps the
      # row `error` with this set, so a create still booting the VM finishes
      # the delete instead of marking the sandbox running.
      add :delete_requested_at, :timestamptz
    end
  end
end
