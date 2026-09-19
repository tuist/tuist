defmodule Tuist.Repo.Migrations.AddAccountsFreeTierResetAt do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :free_tier_reset_at, :timestamptz
    end
  end
end
