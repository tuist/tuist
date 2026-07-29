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

    # Keep the invariant database-backed during rolling deploys. Creating the
    # trigger takes a lock on `accounts`; once it is installed, old replicas
    # that know nothing about concurrency limits still create both rows.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      """
      CREATE FUNCTION create_default_runner_concurrency_limits()
      RETURNS trigger AS $$
      BEGIN
        INSERT INTO runner_concurrency_limits
          (account_id, platform, vcpus, memory_gb, inserted_at, updated_at)
        VALUES
          (NEW.id, 'linux', 32, 64, NOW(), NOW()),
          (NEW.id, 'macos', 12, 28, NOW(), NOW())
        ON CONFLICT (account_id, platform) DO NOTHING;

        RETURN NEW;
      END;
      $$ LANGUAGE plpgsql;
      """,
      "DROP FUNCTION IF EXISTS create_default_runner_concurrency_limits()"
    )

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      """
      CREATE TRIGGER create_default_runner_concurrency_limits
      AFTER INSERT ON accounts
      FOR EACH ROW
      EXECUTE FUNCTION create_default_runner_concurrency_limits()
      """,
      "DROP TRIGGER IF EXISTS create_default_runner_concurrency_limits ON accounts"
    )

    # Backfill accounts that predate the trigger. The unique index makes this
    # safe if account creation overlaps the migration.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute(
      """
      INSERT INTO runner_concurrency_limits
        (account_id, platform, vcpus, memory_gb, inserted_at, updated_at)
      SELECT id, 'linux', 32, 64, NOW(), NOW() FROM accounts
      UNION ALL
      SELECT id, 'macos', 12, 28, NOW(), NOW() FROM accounts
      ON CONFLICT (account_id, platform) DO NOTHING
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
