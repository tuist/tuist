defmodule Tuist.Repo.Migrations.WidenBundleSizeColumnsToBigint do
  # Widen size columns from int4 → int8 online: add a shadow bigint column
  # behind a sync trigger, backfill in batches, atomically swap the two
  # columns at the end. Avoids the multi-minute ACCESS EXCLUSIVE that a
  # plain `ALTER COLUMN ... TYPE bigint` takes on production's 225M-row
  # artifacts table.
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @batch_size 50_000
  @throttle_ms 0

  def up do
    widen("bundles", "install_size", not_null: true)
    widen("bundles", "download_size", not_null: false)
    widen("artifacts", "size", not_null: true)
  end

  def down, do: :ok

  defp widen(table, col, opts) do
    shadow = "#{col}_bigint"
    fn_name = "sync_#{table}_#{col}"
    trigger = "#{fn_name}_trg"

    execute "ALTER TABLE #{table} ADD COLUMN IF NOT EXISTS #{shadow} bigint"

    execute """
    CREATE OR REPLACE FUNCTION #{fn_name}() RETURNS trigger LANGUAGE plpgsql AS $$
    BEGIN NEW.#{shadow} := NEW.#{col}; RETURN NEW; END
    $$
    """

    execute "DROP TRIGGER IF EXISTS #{trigger} ON #{table}"
    execute """
    CREATE TRIGGER #{trigger} BEFORE INSERT OR UPDATE OF #{col} ON #{table}
    FOR EACH ROW EXECUTE FUNCTION #{fn_name}()
    """

    backfill(table, col, shadow)

    if opts[:not_null] do
      # NOT VALID + VALIDATE keeps the validating scan off ACCESS EXCLUSIVE.
      check = "#{shadow}_not_null"
      execute "ALTER TABLE #{table} ADD CONSTRAINT #{check} CHECK (#{shadow} IS NOT NULL) NOT VALID"
      execute "ALTER TABLE #{table} VALIDATE CONSTRAINT #{check}"
      execute "ALTER TABLE #{table} ALTER COLUMN #{shadow} SET NOT NULL"
      execute "ALTER TABLE #{table} DROP CONSTRAINT #{check}"
    end

    execute "DROP TRIGGER #{trigger} ON #{table}"
    execute "DROP FUNCTION #{fn_name}()"

    # Single transaction so concurrent readers never see the column missing.
    repo().transaction(fn ->
      repo().query!("ALTER TABLE #{table} DROP COLUMN #{col}")
      repo().query!("ALTER TABLE #{table} RENAME COLUMN #{shadow} TO #{col}")
    end)
  end

  # UUIDv7 sentinel: lexicographically less than any real id.
  @uuid_zero "00000000-0000-0000-0000-000000000000"

  defp backfill(table, col, shadow, last_id \\ @uuid_zero) do
    page = """
    SELECT id FROM #{table}
    WHERE #{shadow} IS NULL AND id > $1
    ORDER BY id ASC LIMIT #{@batch_size}
    """

    case repo().query!(page, [last_id], timeout: :infinity).rows do
      [] ->
        :ok

      rows ->
        ids = Enum.map(rows, fn [id] -> id end)
        repo().query!("UPDATE #{table} SET #{shadow} = #{col} WHERE id = ANY($1)", [ids],
          timeout: :infinity
        )
        if @throttle_ms > 0, do: Process.sleep(@throttle_ms)
        backfill(table, col, shadow, List.last(ids))
    end
  end
end
