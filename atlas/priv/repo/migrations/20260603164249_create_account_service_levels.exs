defmodule Atlas.Repo.Migrations.CreateAccountServiceLevels do
  use Ecto.Migration

  def change do
    create table(:account_service_level_extraction_checks, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :agent_version, :string, null: false
      add :document_checksum_sha256, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :started_at, :utc_datetime
      add :completed_at, :utc_datetime
      add :last_error, :text
      add :result_summary, :text
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:account_service_level_extraction_checks, [:account_id])
    create index(:account_service_level_extraction_checks, [:document_id])
    create index(:account_service_level_extraction_checks, [:status])
    create unique_index(:account_service_level_extraction_checks, [:document_id, :agent_version])

    create table(:account_service_levels, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all),
        null: false

      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :service_level_extraction_check_id,
          references(:account_service_level_extraction_checks,
            type: :binary_id,
            on_delete: :delete_all
          ),
          null: false

      add :name, :string, null: false
      add :category, :string, null: false
      add :target, :text, null: false
      add :target_value, :decimal, precision: 15, scale: 4
      add :target_unit, :string
      add :measurement_window, :string
      add :applies_from, :date
      add :applies_until, :date
      add :service_credit, :text
      add :exclusions, :text
      add :source_page, :integer
      add :source_excerpt, :text
      add :confidence, :decimal, precision: 5, scale: 4
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:account_service_levels, [:account_id, :category])
    create index(:account_service_levels, [:document_id])
    create index(:account_service_levels, [:service_level_extraction_check_id])
    create index(:account_service_levels, [:applies_until])
  end
end
