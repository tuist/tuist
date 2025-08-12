defmodule Tuist.Repo.Migrations.AddBillingTokenUsagePerformanceIndex do
  use Ecto.Migration

  def change do
    create index(:billing_token_usage, [:account_id, :feature, "timestamp DESC"],
             name: :billing_token_usage_account_feature_timestamp_idx
           )
  end
end
