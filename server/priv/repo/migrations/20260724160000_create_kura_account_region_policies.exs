defmodule Tuist.Repo.Migrations.CreateKuraAccountRegionPolicies do
  use Ecto.Migration

  def change do
    create table(:kura_account_region_policies, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :service_region, :string, null: false
      add :version, :integer, null: false
      add :reason, :text, null: false
      add :assigned_by_user_id, references(:users, on_delete: :nilify_all)
      add :superseded_at, :timestamptz

      timestamps(type: :timestamptz)
    end

    # The table is new and empty, so its constraints and indexes cannot block existing writes.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_service_region_valid,
             check: "service_region IN ('us-east', 'eu-central')"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(
             :kura_account_region_policies,
             :kura_account_region_policies_version_positive,
             check: "version > 0"
           )

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_account_region_policies, [:account_id, :version])

    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:kura_account_region_policies, [:account_id],
             name: :kura_account_region_policies_active_account_index,
             where: "superseded_at IS NULL"
           )
  end
end
