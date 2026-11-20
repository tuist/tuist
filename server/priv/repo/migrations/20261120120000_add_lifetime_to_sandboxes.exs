defmodule Tuist.Repo.Migrations.AddLifetimeToSandboxes do
  use Ecto.Migration

  # A sandbox created through the account API runs at most `lifetime_seconds`
  # after each create or resume, until `expires_at`; integration-owned
  # sandboxes keep both null and never expire.
  def change do
    alter table(:sandboxes) do
      add :lifetime_seconds, :integer
      add :expires_at, :timestamptz
    end
  end
end
