defmodule Atlas.Repo.Migrations.CreateProductTraces do
  use Ecto.Migration

  def change do
    create table(:product_traces, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :provider, :string, null: false, default: "github"
      add :kind, :string, null: false
      add :external_id, :string, null: false

      add :github_repository_id,
          references(:github_repositories, type: :binary_id, on_delete: :delete_all),
          null: false

      add :repository_full_name, :string, null: false
      add :number, :integer, null: false
      add :title, :string, null: false
      add :url, :string, null: false
      add :author_login, :string
      add :occurred_at, :utc_datetime, null: false
      add :labels, {:array, :string}, null: false, default: []
      add :sensitivity, :string, null: false, default: "internal"

      timestamps()
    end

    create unique_index(:product_traces, [:provider, :external_id])
    create index(:product_traces, [:occurred_at])
    create index(:product_traces, [:github_repository_id, :occurred_at])
    create index(:product_traces, [:kind, :occurred_at])

    create constraint(:product_traces, :product_traces_provider_check,
             check: "provider IN ('github')"
           )

    create constraint(:product_traces, :product_traces_kind_check,
             check:
               "kind IN ('pull_request_opened', 'pull_request_merged', 'pull_request_closed', 'issue_opened', 'issue_closed')"
           )

    create constraint(:product_traces, :product_traces_sensitivity_check,
             check: "sensitivity IN ('public', 'internal', 'restricted')"
           )
  end
end
