defmodule Tuist.ClickHouse.Insert do
  @moduledoc """
  A ClickHouse insert a later write waits for on every replica
  (`Tuist.ClickHouse.Inserts`): the rows of `key` in `clickhouse_table`,
  which share `rows_inserted_at` as their `inserted_at`, and when every
  replica was seen holding them (`synced_at`).
  """
  use Ecto.Schema

  @primary_key false
  schema "clickhouse_inserts" do
    field :clickhouse_table, :string, primary_key: true
    field :key, :string, primary_key: true
    field :project_id, :integer
    field :rows_inserted_at, :utc_datetime_usec
    field :synced_at, :utc_datetime_usec
    field :inserted_at, :utc_datetime_usec
  end
end
