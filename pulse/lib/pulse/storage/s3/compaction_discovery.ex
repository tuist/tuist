defmodule Pulse.Storage.S3.CompactionDiscovery do
  @moduledoc """
  Reconstruct compaction tenant discovery from durable tenant prefixes, including idle
  tenants and tenants first ingested on another node. No peer cache is required.

  Delimiter listing returns only immediate tenant directories, not segment keys.
  Owners load metrics manifests; missing manifests never adopt orphan segments.
  Memory grows with tenant count, independently of the segment backlog.

  A LIST is a billed Class A request and every signal's maintenance lane runs
  discovery each pass, so the durable listing is reused node-locally for
  `:compaction_discovery_interval_ms` (10 minutes); tenants this node has
  cached manifests for are added on every pass. A tenant first written on
  another node is maintained here at most one interval later.
  """

  alias Pulse.ObjectStore
  alias Pulse.Storage.S3
  alias Pulse.Storage.S3.ManifestCache
  alias Pulse.Storage.S3.MetadataCache

  def tenants(config) do
    with {:ok, durable} <- durable_tenants(config) do
      local = for signal <- ~w(logs metrics traces), tenant <- ManifestCache.tenants(signal), do: tenant

      # Suspended and deleted tenants get no background work.
      tenants =
        (durable ++ local)
        |> Enum.uniq()
        |> Enum.filter(&(S3.validate_tenant(&1) == :ok and Pulse.Tenants.active?(&1)))
        |> Enum.sort()

      {:ok, tenants}
    end
  end

  defp durable_tenants(config) do
    ref = %{"k" => "tenant-discovery:" <> to_string(config[:endpoint]) <> "/" <> to_string(config[:bucket]), "b" => 1}
    now = System.monotonic_time(:millisecond)

    case MetadataCache.get(ref) do
      {:ok, {listed, tenants}} when is_integer(listed) ->
        if now - listed < Map.get(config, :compaction_discovery_interval_ms, 600_000),
          do: {:ok, tenants},
          else: list_tenants(ref, now, config)

      _ ->
        list_tenants(ref, now, config)
    end
  end

  defp list_tenants(ref, now, config) do
    with {:ok, keys} <- ObjectStore.list_prefixes(config, "tenants/") do
      tenants = keys |> Enum.flat_map(&tenant/1) |> Enum.uniq()
      MetadataCache.put(ref, {now, tenants})
      {:ok, tenants}
    end
  end

  defp tenant(key) do
    case String.split(String.trim_trailing(key, "/"), "/") do
      ["tenants", tenant] ->
        [tenant]

      _ ->
        []
    end
  end
end
