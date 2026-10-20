defmodule Atlas.Repo.Migrations.AddLinkedinOutreachToAccountContacts do
  use Ecto.Migration

  def change do
    alter table(:account_contacts) do
      modify :email, :string, null: true, from: {:string, null: false}
      add :source, :string, null: false, default: "manual"
      add :source_id, :string
      add :linkedin_url, :string
      add :outreach_status, :string, null: false, default: "not_contacted"
      add :outreach_enrolled_at, :utc_datetime
      add :last_outreach_at, :utc_datetime
      add :metadata, :map, null: false, default: %{}
    end

    create unique_index(:account_contacts, [:account_id, :linkedin_url],
             where: "linkedin_url IS NOT NULL",
             name: :account_contacts_account_id_linkedin_url_index
           )

    create unique_index(:account_contacts, [:account_id, :source, :source_id],
             where: "source_id IS NOT NULL",
             name: :account_contacts_account_id_source_source_id_index
           )

    create constraint(:account_contacts, :account_contacts_email_or_linkedin_url,
             check: "email IS NOT NULL OR linkedin_url IS NOT NULL"
           )

    alter table(:account_events) do
      add :contact_id,
          references(:account_contacts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:account_events, [:contact_id, :occurred_at])
  end
end
