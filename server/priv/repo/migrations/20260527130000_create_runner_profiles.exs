defmodule Tuist.Repo.Migrations.CreateRunnerProfiles do
  use Ecto.Migration

  # Account-scoped runner profiles. Customers reference them in
  # `runs-on:` as `tuist-<name>`; the dispatch path resolves
  # `(account, requested-label)` → profile → `(vcpus, memory_gb)` →
  # the pre-rendered shape pool in K8s.
  #
  # Per-profile concurrency caps are not modelled — the account-wide
  # cap (`accounts.runner_max_concurrent`) still gates dispatch.
  def change do
    create table(:runner_profiles) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :vcpus, :integer, null: false
      add :memory_gb, :integer, null: false

      timestamps(type: :timestamptz)
    end

    # One name per account; the dispatch label `tuist-<name>` is
    # account-scoped so two accounts can both have `default`.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_profiles, [:account_id, :name])
  end
end
