defmodule Atlas.Repo.Migrations.AddCustomerPulseCompanySlackPostedAtToAccounts do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :customer_pulse_company_slack_posted_at, :utc_datetime
    end

    create index(:accounts, [:customer_pulse_company_slack_posted_at])
  end
end
