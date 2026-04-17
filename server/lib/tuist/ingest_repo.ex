defmodule Tuist.IngestRepo do
  @moduledoc """
  Write-centric ClickHouse repository.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse

  require Logger

  defoverridable insert_all: 2, insert_all: 3, insert: 1, insert: 2

  def insert_all(schema_or_source, entries, opts \\ []) do
    retry_on_connection_error(fn -> super(schema_or_source, entries, opts) end)
  end

  def insert(struct, opts \\ []) do
    retry_on_connection_error(fn -> super(struct, opts) end)
  end

  defp retry_on_connection_error(fun, retries_left \\ 3) do
    fun.()
  rescue
    e in [Mint.TransportError, DBConnection.ConnectionError] ->
      if retries_left > 0 do
        Logger.warning(
          "ClickHouse operation failed (#{Exception.message(e)}), retrying (#{retries_left} retries left)"
        )

        Process.sleep(100)
        retry_on_connection_error(fun, retries_left - 1)
      else
        reraise e, __STACKTRACE__
      end
  end
end
