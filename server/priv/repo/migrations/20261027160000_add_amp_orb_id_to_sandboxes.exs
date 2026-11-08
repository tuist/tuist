defmodule Tuist.Repo.Migrations.AddAmpOrbIdToSandboxes do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    alter table(:sandboxes) do
      add :amp_orb_id, :string
    end

    create unique_index(:sandboxes, [:account_id, :amp_orb_id], concurrently: true)
  end
end
