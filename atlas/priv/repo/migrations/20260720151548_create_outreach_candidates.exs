defmodule Atlas.Repo.Migrations.CreateOutreachCandidates do
  use Ecto.Migration

  def change do
    create table(:outreach_candidates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string, null: false, default: "apollo"
      add :source_id, :string, null: false
      add :search_segment, :string, null: false
      add :search_version, :integer, null: false, default: 1
      add :status, :string, null: false, default: "pending"
      add :full_name, :string
      add :title, :string
      add :organization_name, :string
      add :organization_source_id, :string
      add :organization_domain, :string
      add :linkedin_url, :text
      add :email, :string
      add :rejection_reason, :string
      add :search_rank, :integer
      add :metadata, :map, null: false, default: %{}
      add :discovered_at, :utc_datetime, null: false
      add :reviewed_at, :utc_datetime

      add :contact_id,
          references(:account_contacts, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:outreach_candidates, [:source, :source_id])
    create index(:outreach_candidates, [:status, :discovered_at])
    create index(:outreach_candidates, [:search_segment])
    create index(:outreach_candidates, [:contact_id])
  end
end
