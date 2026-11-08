defmodule Pulse.Auth.Quota do
  @moduledoc """
  Per-tenant ingest byte quotas published in the issuer status list.

  Each instance enforces `ingest_bytes_per_second × 10 ÷ live instances`
  per ten-second window, where live instances come from
  `Pulse.Auth.IssuerCache.members/0` (clustered nodes or object-store
  heartbeats). This is admission control, not billing-grade metering:
  counters are node-local and reset with the window.
  """

  alias Pulse.Auth.IssuerCache
  alias Pulse.Runtime

  @window_seconds 10

  @doc "Charges `bytes` to `tenant`; `{:error, :rate_limited}` once the window's share is spent."
  def charge(tenant, bytes) when is_binary(tenant) and is_integer(bytes) and bytes >= 0 do
    with ref when ref != :undefined <- :ets.whereis(Runtime.table(__MODULE__)),
         {:ok, _keys, %{quotas: %{^tenant => rate}}} <- IssuerCache.material() do
      window = div(System.os_time(:second), @window_seconds)
      limit = div(rate * @window_seconds, IssuerCache.members())
      used = :ets.update_counter(ref, {tenant, window}, bytes, {{tenant, window}, 0})
      if used <= max(limit, 1), do: :ok, else: {:error, :rate_limited}
    else
      _ -> :ok
    end
  end

  @doc "Drops counters from finished windows."
  def prune do
    with ref when ref != :undefined <- :ets.whereis(Runtime.table(__MODULE__)) do
      current = div(System.os_time(:second), @window_seconds)
      :ets.select_delete(ref, [{{{:_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
    end

    :ok
  end
end
