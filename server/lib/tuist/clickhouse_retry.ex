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
  @max_user_memory_retries 8

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

  def with_result_retry(fun, opts \\ []) do
    transport_retries = Keyword.get(opts, :transport_retries, @max_retries)
    user_memory_retries = Keyword.get(opts, :user_memory_retries, @max_user_memory_retries)

    with_result_retry(fun, transport_retries, transport_retries, user_memory_retries, user_memory_retries)
  end

  def user_memory_limit_error?(%Ch.Error{code: 241, message: message}) do
    String.contains?(message, "for user")
  end

  def user_memory_limit_error?(_error), do: false

  defp with_result_retry(
         fun,
         transport_retries_left,
         initial_transport_retries,
         user_memory_retries_left,
         initial_user_memory_retries
       ) do
    case fun.() do
      {:error, %Ch.Error{} = error} = result ->
        if user_memory_limit_error?(error) and user_memory_retries_left > 0 do
          delay = retry_delay(initial_user_memory_retries, user_memory_retries_left, 2_000)

          Logger.warning(
            "ClickHouse user memory budget is busy, retrying in #{delay}ms (#{user_memory_retries_left} retries left)"
          )

          Process.sleep(delay)

          with_result_retry(
            fun,
            transport_retries_left,
            initial_transport_retries,
            user_memory_retries_left - 1,
            initial_user_memory_retries
          )
        else
          result
        end

      {:error, error} = result when is_struct(error, Mint.TransportError) ->
        retry_transport_result(
          fun,
          result,
          error,
          transport_retries_left,
          initial_transport_retries,
          user_memory_retries_left,
          initial_user_memory_retries
        )

      {:error, error} = result when is_struct(error, DBConnection.ConnectionError) ->
        retry_transport_result(
          fun,
          result,
          error,
          transport_retries_left,
          initial_transport_retries,
          user_memory_retries_left,
          initial_user_memory_retries
        )

      result ->
        result
    end
  end

  defp retry_transport_result(
         fun,
         result,
         error,
         transport_retries_left,
         initial_transport_retries,
         user_memory_retries_left,
         initial_user_memory_retries
       ) do
    if transport_retries_left > 0 do
      delay = retry_delay(initial_transport_retries, transport_retries_left)

      Logger.warning(
        "ClickHouse operation failed (#{Exception.message(error)}), retrying in #{delay}ms (#{transport_retries_left} retries left)"
      )

      Process.sleep(delay)

      with_result_retry(
        fun,
        transport_retries_left - 1,
        initial_transport_retries,
        user_memory_retries_left,
        initial_user_memory_retries
      )
    else
      result
    end
  end

  defp retry_delay(max_retries, retries_left, maximum \\ :infinity) do
    delay = Integer.pow(2, max_retries - retries_left) * 100
    if maximum == :infinity, do: delay, else: min(delay, maximum)
  end
end
