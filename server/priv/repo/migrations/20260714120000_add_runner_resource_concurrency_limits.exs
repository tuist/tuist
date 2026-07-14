defmodule Tuist.Repo.Migrations.AddRunnerResourceConcurrencyLimits do
  use Ecto.Migration

  def change do
    create table(:runner_concurrency_limits) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :platform, :string, null: false
      add :vcpus, :integer, null: false
      add :memory_gb, :integer, null: false

      timestamps(type: :timestamptz)
    end

    # The table is new and empty, so building its unique index inline cannot block writes.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently
    create unique_index(:runner_concurrency_limits, [:account_id, :platform])

    # These constraints are added before the table is backfilled, so no existing rows need validation.
    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:runner_concurrency_limits, :runner_concurrency_limits_platform,
             check: "platform IN ('linux', 'macos')"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:runner_concurrency_limits, :runner_concurrency_limits_positive_vcpus,
             check: "vcpus > 0"
           )

    # excellent_migrations:safety-assured-for-next-line check_constraint_added
    create constraint(:runner_concurrency_limits, :runner_concurrency_limits_positive_memory,
             check: "memory_gb > 0"
           )

    # Backfill the new table with the default policy before new account creation starts writing rows.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      """
      INSERT INTO runner_concurrency_limits
        (account_id, platform, vcpus, memory_gb, inserted_at, updated_at)
      SELECT id, 'linux', 32, 64, NOW(), NOW() FROM accounts
      UNION ALL
      SELECT id, 'macos', 12, 28, NOW(), NOW() FROM accounts
      """,
      "DELETE FROM runner_concurrency_limits"
    )

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
