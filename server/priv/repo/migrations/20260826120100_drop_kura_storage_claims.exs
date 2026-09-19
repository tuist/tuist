defmodule Tuist.Repo.Migrations.DropKuraStorageClaims do
  use Ecto.Migration

  # The per-account claim override existed because a plan predicted an
  # account's working set badly and someone had to correct it by hand. Sizing
  # measures the working set now, so the correction has no author left: the
  # table held no rows in production, and the remaining reason to keep it was
  # as a per-account exemption from sizing, which the fleet-wide pause switch
  # covers instead.
  #
  # Must run after the preceding migration pins every unpinned governed
  # instance, since that one reads nothing from here but shares its purpose:
  # no instance's disk should change size because a default moved.
  def up do
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:kura_storage_claims)
  end

  def down do
    create table(:kura_storage_claims) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :claim_size, :string, null: false

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_storage_claims, [:account_id])
  end
end
