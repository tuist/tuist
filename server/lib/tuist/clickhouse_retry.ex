defmodule Tuist.ClickHouseRetry do
  @moduledoc """
  Retry helper for `ClickHouseRepo` calls hit by transient transport
  errors.

  The xcresult-processor pods on Scaleway Mac minis reach ClickHouse
  Cloud over public-internet HTTPS. Idle pool sockets occasionally get
  dropped by intermediate NAT and surface on the next checkout as
  `Mint.TransportError{reason: :closed}`; in-flight queries on a
  half-dead socket surface as `Mint.TransportError{reason: :timeout}`.
  Both are safe to retry on idempotent reads.

  Wrap the read in `run/1`. Three attempts total with linear backoff
  (200ms, 400ms). Anything other than `Mint.TransportError` propagates
  unchanged so genuine bugs are not masked.
  """

  require Logger

  @attempts 3
  @base_backoff_ms 200

  def run(fun) when is_function(fun, 0), do: do_run(fun, 1)

  defp do_run(fun, attempt) do
    fun.()
  rescue
    e in Mint.TransportError ->
      if attempt >= @attempts do
        reraise e, __STACKTRACE__
      else
        Logger.warning(
          "ClickHouse transport error (attempt #{attempt}/#{@attempts}): #{Exception.message(e)}"
        )

        Process.sleep(@base_backoff_ms * attempt)
        do_run(fun, attempt + 1)
      end
  end
end
