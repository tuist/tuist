defmodule Tuist.ClickHouse.Insert do
  @moduledoc """
  A ClickHouse insert a later write waits for on every replica
  (`Tuist.ClickHouse.Inserts`): the rows of `key` in `clickhouse_table`,
  which share `rows_inserted_at` as their `inserted_at` (or, for buffered
  rows, were all inserted at or after it), and when every replica was seen
  holding them (`synced_at`). `row_count` is how many rows the insert wrote,
  nil while it is declared but not yet written, and `git_commit_sha` the
  commit whose fold reads them (`Tuist.Tests.Coverage.RunInputs`).
  """
  use Ecto.Schema

  @primary_key false
  schema "clickhouse_inserts" do
    field :clickhouse_table, :string, primary_key: true
    field :key, :string, primary_key: true
    field :project_id, :integer
    field :rows_inserted_at, :utc_datetime_usec
    field :row_count, :integer
    field :git_commit_sha, :string
    field :synced_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
