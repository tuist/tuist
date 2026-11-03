defmodule Tuist.IngestRepo do
  @moduledoc """
  Write-only ClickHouse repository. Reads belong on
  `Tuist.ClickHouseRepo`.
  """

  use Ecto.Repo,
    otp_app: :tuist,
    adapter: Ecto.Adapters.ClickHouse

  use Tuist.ClickHouse.ArrayInParams

  alias Tuist.ClickHouseRetry

  defoverridable insert_all: 2, insert_all: 3, insert: 1, insert: 2

  def insert_all(schema_or_source, entries, opts \\ []) do
    {retry?, opts} = Keyword.pop(opts, :retry, true)
    opts = remaining_timeout(opts)
    retries = if retry?, do: [], else: [transport_retries: 0, memory_retries: 0]
    with_retry(fn -> super(schema_or_source, entries, opts) end, retries)
  end

  def insert(struct, opts \\ []) do
    with_retry(fn -> super(struct, opts) end)
  end

  defp remaining_timeout(opts) do
    case opts[:deadline] do
      nil ->
        opts

      deadline ->
        remaining = deadline - System.monotonic_time(:millisecond)

        if remaining <= 0, do: raise(DBConnection.ConnectionError, "ingestion deadline exceeded")

        # Ch's receive timeout is separate from DBConnection's absolute deadline.
        Keyword.put(opts, :timeout, remaining)
    end
  end

  defdelegate with_retry(fun), to: ClickHouseRetry
  defdelegate with_retry(fun, opts), to: ClickHouseRetry
end
