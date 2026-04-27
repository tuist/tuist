defmodule Tuist.Repo.Migrations.WidenBundleSizeColumnsToBigint do
  # Widen bundles.install_size, bundles.download_size, and artifacts.size
  # from int4 → int8 without taking ACCESS EXCLUSIVE on the hot path.
  #
  # `ALTER COLUMN ... TYPE bigint` rewrites the table holding the table
  # exclusively for the duration of the rewrite. On production's 225M-row
  # artifacts table that runs for 10s of minutes, blocking every read and
  # write to the table — bundle uploads time out, cache lookups fail.
  #
  # Online pattern instead:
  #   1. Add nullable `*_bigint` shadow column (metadata only, instant).
  #   2. Install a trigger that mirrors the int column → bigint column on
  #      INSERT/UPDATE so concurrent writes from the still-running old code
  #      keep both columns in sync.
  #   3. Backfill historical rows in throttled batches (no table lock,
  #      restartable on `WHERE *_bigint IS NULL`).
  #   4. Validate NOT NULL via NOT VALID + VALIDATE (briefly takes ACCESS
  #      EXCLUSIVE for the metadata flip, but no rewrite).
  #   5. Drop trigger + function.
  #   6. Inside a single transaction: drop the int column, rename the
  #      bigint column to take its place. Both are metadata-only — readers
  #      and writers see the swap atomically.
  #
  # Idempotency: the migration runs on environments where the simple
  # ALTER COLUMN already succeeded (canary, staging, dev). It bails early
  # when the column is already bigint, so re-running on a fresh DB is a
  # no-op once the swap has happened.
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # Tuned for ~25-35 minutes of total wall-clock on 225M rows under
  # Supabase's pooler. Each batch holds row locks for ~200-400ms, fine for
  # bundle uploads that retry on lock contention. No throttle: backfill is
  # the only writer that touches the shadow column, and concurrent old-code
  # writes go through the trigger which is cheap.
  @batch_size 50_000
  @throttle_ms 0

  def up do
    if column_is_bigint?("artifacts", "size") do
      :ok
    else
      widen("bundles", "install_size", required: true)
      widen("bundles", "download_size", required: false)
      widen("artifacts", "size", required: true)
    end
  end

  def down do
    # No-op: shrinking bigint → int risks truncating live values that
    # motivated this migration in the first place.
    :ok
  end

  defp widen(table, col, required: required) do
    new_col = "#{col}_bigint"
    fn_name = "tuist_sync_#{table}_#{col}_bigint"
    trigger = "tuist_sync_#{table}_#{col}_bigint_trg"
    constraint = "#{new_col}_not_null"

    # Step 1: add the shadow column (metadata only).
    execute "ALTER TABLE #{table} ADD COLUMN IF NOT EXISTS #{new_col} bigint"

    # Step 2: trigger keeps the shadow column in lockstep with writes from
    # the currently-running old code. CREATE OR REPLACE + DROP IF EXISTS so
    # a partially-applied migration restarts cleanly.
    execute """
    CREATE OR REPLACE FUNCTION #{fn_name}() RETURNS trigger
    LANGUAGE plpgsql AS $$
    BEGIN
      NEW.#{new_col} := NEW.#{col};
      RETURN NEW;
    END
    $$
    """

    execute "DROP TRIGGER IF EXISTS #{trigger} ON #{table}"

    execute """
    CREATE TRIGGER #{trigger}
    BEFORE INSERT OR UPDATE OF #{col} ON #{table}
    FOR EACH ROW EXECUTE FUNCTION #{fn_name}()
    """

    # Step 3: backfill old rows in throttled batches.
    backfill(table, col, new_col)

    # Step 4: enforce NOT NULL via the online NOT VALID + VALIDATE pattern
    # so the validating scan doesn't hold ACCESS EXCLUSIVE on the table.
    if required do
      execute """
      ALTER TABLE #{table}
      ADD CONSTRAINT #{constraint}
      CHECK (#{new_col} IS NOT NULL) NOT VALID
      """

      execute "ALTER TABLE #{table} VALIDATE CONSTRAINT #{constraint}"
      execute "ALTER TABLE #{table} ALTER COLUMN #{new_col} SET NOT NULL"
      execute "ALTER TABLE #{table} DROP CONSTRAINT #{constraint}"
    end

    # Step 5: trigger no longer needed once we own the column.
    execute "DROP TRIGGER #{trigger} ON #{table}"
    execute "DROP FUNCTION #{fn_name}()"

    # Step 6: atomic swap. Inside a single transaction so concurrent
    # connections never observe the column missing — they see either the
    # old int column or the new bigint column, never neither.
    repo().transaction(fn ->
      repo().query!("ALTER TABLE #{table} DROP COLUMN #{col}", [], log: :info)
      repo().query!("ALTER TABLE #{table} RENAME COLUMN #{new_col} TO #{col}", [], log: :info)
    end)
  end

  defp backfill(table, col, new_col) do
    page_query = fn last_id ->
      """
      SELECT id FROM #{table}
      WHERE #{new_col} IS NULL AND id > $1
      ORDER BY id ASC
      LIMIT #{@batch_size}
      """
    end

    update_query = fn ->
      """
      UPDATE #{table} SET #{new_col} = #{col}
      WHERE id = ANY($1) AND #{new_col} IS NULL
      """
    end

    # UUIDv7 minimum — sortable, lexicographically less than any real id.
    sentinel = "00000000-0000-0000-0000-000000000000"
    backfill_loop(page_query, update_query, sentinel)
  end

  defp backfill_loop(page_query, update_query, last_id) do
    case repo().query!(page_query.(last_id), [last_id], log: :info, timeout: :infinity) do
      %{rows: []} ->
        :ok

      %{rows: rows} ->
        ids = Enum.map(rows, fn [id] -> id end)
        repo().query!(update_query.(), [ids], log: :info, timeout: :infinity)
        Process.sleep(@throttle_ms)
        backfill_loop(page_query, update_query, List.last(ids))
    end
  end

  defp column_is_bigint?(table, col) do
    case repo().query!(
           "SELECT data_type FROM information_schema.columns " <>
             "WHERE table_name = $1 AND column_name = $2",
           [table, col]
         ) do
      %{rows: [["bigint"]]} -> true
      _ -> false
    end
  end
end
