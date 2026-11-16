defmodule Tuist.Repo.Migrations.RecordRunnerConcurrencyHistory do
  use Ecto.Migration

  def up do
    create table(:runner_concurrency_history) do
      add :account_id, references(:accounts, on_delete: :delete_all), null: false
      add :platform, :string, null: false
      add :vcpus, :integer, null: false
      add :memory_gb, :integer, null: false
      add :source, :string, null: false
      add :reason, :text, null: false, default: ""
      add :recorded_at, :timestamptz, null: false, default: fragment("clock_timestamp()")
    end

    # This is a new, empty table; the four columns support the account/platform
    # range scan and deterministic ordering of changes with the same timestamp.
    # excellent_migrations:safety-assured-for-next-line index_not_concurrently many_columns_index
    create index(:runner_concurrency_history, [:account_id, :platform, :recorded_at, :id])

    # The trigger also covers old application replicas and direct operator
    # updates. The limit and its history always commit or roll back together.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE FUNCTION record_runner_concurrency_history() RETURNS trigger AS $$
    BEGIN
      IF TG_OP = 'UPDATE' THEN
        IF NEW.vcpus = OLD.vcpus AND NEW.memory_gb = OLD.memory_gb THEN
          RETURN NEW;
        END IF;
      END IF;
      INSERT INTO runner_concurrency_history
        (account_id, platform, vcpus, memory_gb, source, reason)
      VALUES (NEW.account_id, NEW.platform, NEW.vcpus, NEW.memory_gb,
        CASE WHEN TG_OP = 'INSERT' THEN 'initial'
          ELSE COALESCE(NULLIF(current_setting('tuist.runner_concurrency_source', true), ''), 'manual') END,
        COALESCE(current_setting('tuist.runner_concurrency_reason', true), ''));
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    """

    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    CREATE TRIGGER record_runner_concurrency_history
    AFTER INSERT OR UPDATE ON runner_concurrency_limits
    FOR EACH ROW EXECUTE FUNCTION record_runner_concurrency_history();
    """

    # The DDL lock excludes concurrent limit changes until this baseline is
    # recorded. We know today's values, not when older grants were made.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute """
    INSERT INTO runner_concurrency_history (account_id, platform, vcpus, memory_gb, source)
    SELECT account_id, platform, vcpus, memory_gb, 'baseline'
    FROM runner_concurrency_limits
    """
  end

  def down do
    # Roll back the application before removing its history dependency.
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP TRIGGER record_runner_concurrency_history ON runner_concurrency_limits"
    # excellent_migrations:safety-assured-for-next-line raw_sql_executed
    execute "DROP FUNCTION record_runner_concurrency_history()"
    # excellent_migrations:safety-assured-for-next-line table_dropped
    drop table(:runner_concurrency_history)
  end
end
