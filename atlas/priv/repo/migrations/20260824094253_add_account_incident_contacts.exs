defmodule Atlas.Repo.Migrations.AddAccountIncidentContacts do
  use Ecto.Migration

  def change do
    create table(:account_incident_contacts, primary_key: false) do
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

      add :email, :string, null: false
      add :full_name, :string
      add :role, :string
      add :source_page, :integer
      add :source_excerpt, :text
      add :confidence, :decimal, precision: 5, scale: 4
      add :metadata, :map, null: false, default: %{}

      timestamps()
    end

    create index(:account_incident_contacts, [:account_id])
    create index(:account_incident_contacts, [:document_id])
    create index(:account_incident_contacts, [:service_level_extraction_check_id])
    create unique_index(:account_incident_contacts, [:document_id, :email])
  end
end
