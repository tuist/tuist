defmodule Tuist.IngestRepo do
  @moduledoc """
  Write-centric ClickHouse repository.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse

  alias Tuist.ClickHouseRetry

  defoverridable insert_all: 2, insert_all: 3, insert: 1, insert: 2, all: 1, all: 2

  def insert_all(schema_or_source, entries, opts \\ []) do
    with_retry(fn -> super(schema_or_source, entries, opts) end)
  end

  def insert(struct, opts \\ []) do
    with_retry(fn -> super(struct, opts) end)
  end

  def all(queryable, opts \\ []) do
    with_retry(fn -> super(queryable, opts) end)
  end

  defdelegate with_retry(fun), to: ClickHouseRetry
  defdelegate with_retry(fun, retries_left), to: ClickHouseRetry
end
