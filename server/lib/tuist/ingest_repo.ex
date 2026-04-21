defmodule Tuist.IngestRepo do
  @moduledoc """
  Write-centric ClickHouse repository.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse

  require Logger

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

  @max_retries 3

  def with_retry(fun, retries_left \\ @max_retries) do
    fun.()
  rescue
    e in [Mint.TransportError, DBConnection.ConnectionError] ->
      if retries_left > 0 do
        delay = Integer.pow(2, @max_retries - retries_left) * 100

        Logger.warning(
          "ClickHouse operation failed (#{Exception.message(e)}), retrying in #{delay}ms (#{retries_left} retries left)"
        )

        Process.sleep(delay)
        with_retry(fun, retries_left - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
