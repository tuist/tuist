defmodule Tuist.Repo.Migrations.AddProtectedToRunnerProfiles do
  use Ecto.Migration

  # `protected` marks profiles the system auto-creates on account
  # bootstrap (currently the per-account `linux` default). Their
  # shape stays editable so customers can right-size; only the row
  # itself can't be deleted, so every account always has at least
  # one Linux profile and the default `tuist-<env>-linux` /
  # `tuist-linux` label keeps resolving.
  def change do
    alter table(:runner_profiles) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :protected, :boolean, null: false, default: false
    end
  end
end
