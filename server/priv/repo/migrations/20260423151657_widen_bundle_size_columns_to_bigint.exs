defmodule Tuist.Repo.Migrations.WidenBundleSizeColumnsToBigint do
  # Widen size columns from int4 → int8 online: add a nullable shadow
  # bigint column, backfill in batches, atomically swap the two columns at
  # the end. Avoids the multi-minute ACCESS EXCLUSIVE a plain
  # `ALTER COLUMN ... TYPE bigint` takes on production's 225M-row artifacts
  # table.
  #
  # Trade-off: rows inserted between the bulk backfill and the swap end up
  # with a NULL shadow value (no sync trigger). Those become NULL on the
  # renamed column post-swap. We accept that — at production write rates
  # the window is small and "a few NULL bundle sizes" is preferable to the
  # function/trigger boilerplate. The renamed column is therefore nullable;
  # restoring NOT NULL is a follow-up once the stragglers are reconciled.
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  @batch_size 50_000
  @throttle_ms 0

  def up do
    widen("bundles", "install_size")
    widen("bundles", "download_size")
    widen("artifacts", "size")
  end

  def down, do: :ok

  defp widen(table, col) do
    if column_type(table, col) == "bigint" do
      :ok
    else
      shadow = "#{col}_bigint"

      # `execute` queues DDL through the migration runner; we mix raw
      # `repo().query!` calls in the backfill, so go direct here too —
      # otherwise the ADD COLUMN hasn't actually run when backfill looks
      # for the shadow column.
      repo().query!("ALTER TABLE #{table} ADD COLUMN IF NOT EXISTS #{shadow} bigint")

      backfill(table, col, shadow)

      # PostgreSQL has no single-statement column swap; DROP + RENAME inside
      # a transaction is the canonical pattern. The transaction keeps the
      # change atomic from a reader's perspective — they see either the old
      # int column or the new bigint column, never neither.
      repo().transaction(fn ->
        repo().query!("ALTER TABLE #{table} DROP COLUMN #{col}")
        repo().query!("ALTER TABLE #{table} RENAME COLUMN #{shadow} TO #{col}")
      end)
    end
  end

  defp column_type(table, col) do
    case repo().query!(
           "SELECT data_type FROM information_schema.columns " <>
             "WHERE table_name = $1 AND column_name = $2",
           [table, col]
         ) do
      %{rows: [[type]]} -> type
      _ -> nil
    end
  end

  # 16 zero bytes: lexicographically less than any real UUID. Postgrex's
  # uuid type wants the raw binary, not the hyphenated string form.
  @uuid_zero <<0::128>>

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
