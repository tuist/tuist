defmodule Atlas.Repo.Migrations.CreateGtmOutreachOpportunities do
  use Ecto.Migration

  def change do
    create table(:gtm_signal_queries, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :source, :string, null: false
      add :query, :text, null: false
      add :enabled, :boolean, null: false, default: true
      add :result_limit, :integer, null: false, default: 5
      add :metadata, :map, null: false, default: %{}
      add :last_run_at, :utc_datetime

      timestamps()
    end

    create unique_index(:gtm_signal_queries, [:source, :query])
    create index(:gtm_signal_queries, [:enabled])

    create table(:gtm_opportunities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :company_key, :string, null: false
      add :company_name, :string, null: false
      add :domain, :string
      add :status, :string, null: false, default: "new"
      add :score, :integer, null: false, default: 0
      add :score_breakdown, :map, null: false, default: %{}
      add :rationale, :text
      add :signal_summary, :text
      add :latest_signal_at, :utc_datetime
      add :reviewed_at, :utc_datetime
      add :rejected_reason, :text
      add :account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)

      timestamps()
    end

    create unique_index(:gtm_opportunities, [:company_key])
    create unique_index(:gtm_opportunities, [:domain], where: "domain IS NOT NULL")
    create index(:gtm_opportunities, [:status, :score])
    create index(:gtm_opportunities, [:account_id])
    create index(:gtm_opportunities, [:latest_signal_at])

    create table(:gtm_signals, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string, null: false
      add :source_ref, :text, null: false
      add :source_url, :text
      add :title, :text, null: false
      add :excerpt, :text
      add :matched_terms, {:array, :string}, null: false, default: []
      add :signal_kind, :string, null: false
      add :confidence, :integer, null: false, default: 0
      add :observed_at, :utc_datetime, null: false
      add :metadata, :map, null: false, default: %{}
      add :query_id, references(:gtm_signal_queries, type: :binary_id, on_delete: :nilify_all)

      add :opportunity_id,
          references(:gtm_opportunities, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create unique_index(:gtm_signals, [:source, :source_ref])
    create index(:gtm_signals, [:opportunity_id])
    create index(:gtm_signals, [:query_id])
    create index(:gtm_signals, [:signal_kind])
    create index(:gtm_signals, [:observed_at])

    create table(:gtm_opportunity_contacts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :source, :string, null: false, default: "apollo"
      add :full_name, :string
      add :title, :string, null: false
      add :organization_name, :string
      add :linkedin_url, :text
      add :email, :string
      add :confidence, :integer, null: false, default: 0
      add :metadata, :map, null: false, default: %{}

      add :opportunity_id,
          references(:gtm_opportunities, type: :binary_id, on_delete: :delete_all), null: false

      timestamps()
    end

    create index(:gtm_opportunity_contacts, [:opportunity_id])

    create unique_index(:gtm_opportunity_contacts, [:opportunity_id, :linkedin_url],
             where: "linkedin_url IS NOT NULL"
           )
  end
end
