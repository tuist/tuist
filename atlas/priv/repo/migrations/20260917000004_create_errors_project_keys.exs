defmodule Atlas.Repo.Migrations.CreateErrorsProjectKeys do
  use Ecto.Migration

  def up do
    execute "CREATE SEQUENCE errors_project_keys_dsn_project_id_seq"

    create table(:errors_project_keys, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :project_id, references(:projects, type: :binary_id, on_delete: :delete_all), null: false
      add :domain_id, references(:domains, type: :binary_id, on_delete: :delete_all)
      add :public_key, :string, size: 32, null: false
      add :secret_key, :string, size: 32
      add :name, :string, null: false, default: "default"
      add :last_used_at, :utc_datetime_usec

      add :dsn_project_id, :bigint,
        null: false,
        default: fragment("nextval('errors_project_keys_dsn_project_id_seq')")

      add :created_by_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :timestamptz)
    end

    create unique_index(:errors_project_keys, [:public_key])
    create index(:errors_project_keys, [:project_id])
    create index(:errors_project_keys, [:domain_id])
    create unique_index(:errors_project_keys, [:dsn_project_id])

    create unique_index(
             :errors_project_keys,
             [:project_id, :domain_id],
             where: "domain_id IS NOT NULL",
             name: :errors_project_keys_project_id_domain_id_index
           )
  end

  def down do
    drop table(:errors_project_keys)
    execute "DROP SEQUENCE errors_project_keys_dsn_project_id_seq"
  end
end
