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

  Used by `Tuist.IngestRepo` (writes) and `Tuist.ClickHouseRepo`
  (reads) so every Repo call inherits the retry without per-call-site
  wrapping.
  """

  require Logger

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
