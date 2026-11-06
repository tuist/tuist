defmodule Tuist.Repo.Migrations.CreateKuraTenantKeys do
  use Ecto.Migration

  def change do
    create table(:kura_tenant_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :version, :integer, null: false
      add :shares, {:array, :map}, null: false
      add :state, :string, null: false, default: "active"

      timestamps(type: :timestamptz)
    end

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_tenant_keys, [:account_id, :version])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_tenant_keys, [:account_id],
             name: :kura_tenant_keys_one_active_per_account_index,
             where: "state = 'active'"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:kura_tenant_keys, :kura_tenant_keys_state_valid,
             check: "state IN ('active', 'retired')"
           )
  end
end
