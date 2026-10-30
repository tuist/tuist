defmodule Tuist.ClickHouse.IndexMaterialization do
  @moduledoc """
  Builds an existing table's skip index one partition at a time.

  A whole-table `MATERIALIZE INDEX` is a single mutation over every part, so
  the table's size, not its retention, decides how much it does at once. One
  mutation per partition bounds each unit of work to one partition, a
  mutation that builds an index reads only the indexed columns, and
  `mutations_sync = 0` returns before any of it runs, so a deploy that runs
  the migration does not wait on it.
  """

  @doc """
  One `MATERIALIZE INDEX` per partition, each an asynchronous mutation.
  """
  def materialize_index_statements(database, table, name, partition_ids) do
    Enum.map(partition_ids, fn partition_id ->
      "ALTER TABLE #{quote_ident(database)}.#{quote_ident(table)} " <>
        "MATERIALIZE INDEX #{quote_ident(name)} IN PARTITION ID '#{escape_literal(partition_id)}' " <>
        "SETTINGS mutations_sync = 0"
    end)
  end

  @doc """
  The active partition IDs of `table`, for `materialize_index_statements/4`.
  """
  def partition_ids(repo, database, table) do
    %{rows: rows} =
      repo.query!(
        """
        SELECT DISTINCT partition_id FROM system.parts
        WHERE database = {database:String} AND table = {table:String} AND active
        ORDER BY partition_id
        """,
        %{"database" => database, "table" => table},
        log: false
      )

    Enum.map(rows, &hd/1)
  end

  defp quote_ident(name), do: "`" <> String.replace(to_string(name), "`", "``") <> "`"

  defp escape_literal(value), do: String.replace(value, ["\\", "'"], fn char -> "\\" <> char end)
end
