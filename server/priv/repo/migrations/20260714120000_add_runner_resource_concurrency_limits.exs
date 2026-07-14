defmodule Tuist.Repo.Migrations.AddRunnerResourceConcurrencyLimits do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :runner_linux_vcpus_limit, :integer, null: false, default: 32

      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :runner_linux_memory_gb_limit, :integer, null: false, default: 64

      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :runner_macos_vcpus_limit, :integer, null: false, default: 12

      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :runner_macos_memory_gb_limit, :integer, null: false, default: 28
    end

    alter table(:runner_claims) do
      # Existing claims are short-lived and predate resource accounting.
      # Zero-sized Linux defaults keep them loadable by Ecto while allowing
      # new claims to carry their exact platform-specific resources.
      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :platform, :string, null: false, default: "linux"

      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :vcpus, :integer, null: false, default: 0

      # excellent_migrations:safety-assured-for-next-line column_added_with_default
      add :memory_gb, :integer, null: false, default: 0
    end

    # Supports the per-account, per-platform SUM used in the atomic
    # concurrency check and on the customer-facing Runners page.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create index(:runner_claims, [:account_id, :platform])
  end
end
