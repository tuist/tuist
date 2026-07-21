defmodule Tuist.ClickHouseRetry do
  @moduledoc """
  Retry helper for ClickHouse driver operations that can transiently
  fail with `Mint.TransportError` or `DBConnection.ConnectionError`.

  The xcresult-processor pods on Scaleway Mac minis reach ClickHouse
  Cloud over public-internet HTTPS, where idle pool sockets get
  reaped by intermediate NAT and surface on the next checkout as
  `Mint.TransportError{reason: :closed}`; in-flight queries on a
  half-dead socket surface as `:timeout`. Both clear within
  milliseconds and are safe to retry on idempotent reads/writes.

  Used by `Tuist.IngestRepo` (writes: `insert`, `insert_all`, `all`)
  and `Tuist.ClickHouseRepo` (reads: `all`, `one`, `aggregate`,
  `exists?`, `preload`, `query`, `query!`) so every wired Repo call
  inherits the retry without per-call-site wrapping. `stream/1,2` and
  cursor-based reads are intentionally left out: a retry mid-iteration
  can't recover the producer's position cleanly.
  """

  require Logger

  @max_retries 3

  @retryable_errors [Mint.TransportError, DBConnection.ConnectionError]

  @doc """
  Same retry policy as `with_retry/2`, for callers that use the non-bang
  `query/3` and get `{:error, exception}` back instead of a raise.

  `with_retry/2` can only see failures that are raised, so it is unusable from
  a `GenServer.handle_call/3` that must not die on a bad query — the raise it
  re-raises would take the process, and every caller blocked on it, down with
  it. This variant keeps the same backoff while letting the caller decide what
  a failure means.
  """
  def with_retry_result(fun, retries_left \\ @max_retries) do
    case fun.() do
      {:ok, _result} = ok ->
        ok

      {:error, %error_module{} = error} when error_module in @retryable_errors ->
        if retries_left > 0 do
          delay = backoff_ms(retries_left)

          Logger.warning(
            "ClickHouse operation failed (#{Exception.message(error)}), retrying in #{delay}ms (#{retries_left} retries left)"
          )

          Process.sleep(delay)
          with_retry_result(fun, retries_left - 1)
        else
          {:error, error}
        end

      {:error, _error} = error ->
        error
    end
  end

  defp backoff_ms(retries_left), do: Integer.pow(2, @max_retries - retries_left) * 100

  def with_retry(fun, retries_left \\ @max_retries) do
    fun.()
  rescue
    e in [Mint.TransportError, DBConnection.ConnectionError] ->
      if retries_left > 0 do
        delay = backoff_ms(retries_left)

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
