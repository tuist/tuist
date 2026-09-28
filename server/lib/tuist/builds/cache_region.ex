defmodule Tuist.Builds.CacheRegion do
  @moduledoc """
  Where a build came from, which cache region served it, and which region
  should have.

  A managed account's stable hostname (`<handle>.cache.tuist.dev`) is routed by
  latency records the client's own resolver picks, so a VPN or a corporate
  resolver can send a build to a region far from where the machine is, and
  every cache key then costs a cross-continent round trip. Nothing on our side
  chooses that region, so the build report is where it has to show.

    * The client origin is the Cloudflare-derived label
      (`TuistWeb.RemoteIp.attributed_origin/1`) of the request that uploaded
      the build, the same label `/api/cache/endpoints` resolves regions from.
    * The expected region is the region placement would pick for that origin
      among the account's serving managed regions, nearest first
      (`Tuist.Kura.managed_cache_endpoints/2`).
    * The serving region is what Kura named on the responses the CAS proxy
      recorded for this build's reads, writes and transfers.

  Region and origin labels only. No addresses, resolvers or VPN detection.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Kura
  alias Tuist.Kura.Regions

  @doc """
  The client origin and the region expected to serve it, as build attributes.
  Both are empty when there is nothing to compare against: an unattributed
  request, or an account with no serving managed region.
  """
  def client_attrs(%Account{} = account, origin) when is_binary(origin) and origin != "" do
    %{client_origin: origin, cache_expected_region: expected_region(account, origin) || ""}
  end

  def client_attrs(_account, _origin), do: %{client_origin: "", cache_expected_region: ""}

  @doc """
  The region nearest `origin` among the account's serving managed regions, or
  `nil` when the account has none.
  """
  def expected_region(%Account{} = account, origin) do
    case Kura.managed_cache_endpoints(account, origin) do
      [%{region: region} | _] -> region
      [] -> nil
    end
  end

  @doc """
  The parser's `cache_serving` summary (decoded JSON, string keys) as build
  attributes. A build whose
  proxy recorded no answering region (an older proxy or Kura, a build with no
  remote cache traffic) has none.
  """
  def serving_attrs(%{} = serving) do
    region = serving["region"]

    if is_binary(region) and region != "" do
      %{
        cache_serving_region: region,
        cache_serving_node: serving["node"] || "",
        cache_serving_region_requests: count(serving["region_requests"]),
        cache_observed_requests: count(serving["observed_requests"]),
        cache_connected_at: connected_at(serving["connected_at"]),
        cache_connected_before_build_seconds: optional_count(serving["connected_before_build_seconds"])
      }
    else
      %{}
    end
  end

  def serving_attrs(_serving), do: %{}

  @doc """
  How the serving region compares with the expected one:

    * `:match` and `:mismatch` when both are known and the serving region is
      one a customer's resolver can reach.
    * `:unknown` otherwise. A private region (the runner cache) or a
      self-hosted region is reached by configuration, not by DNS, so it says
      nothing about the client's network.
  """
  def verdict(%{cache_expected_region: expected, cache_serving_region: serving})
      when is_binary(expected) and expected != "" and is_binary(serving) and serving != "" do
    cond do
      not comparable?(serving) -> :unknown
      serving == expected -> :match
      true -> :mismatch
    end
  end

  def verdict(_build), do: :unknown

  @doc """
  What a build report shows about the cache region, or `nil` when the build
  recorded none of it.

  `connected_before_build_seconds` is how long the connection that served the
  build had been open when the build started (0 when it opened during the
  build), measured by the parser against the activity log's start. The CAS
  proxy renews connections after its ten-minute endpoint freshness window and
  on network changes, so a small value rules out a connection we kept from a
  network the machine has since left.
  """
  def summary(build) do
    fields = [
      Map.get(build, :client_origin),
      Map.get(build, :cache_expected_region),
      Map.get(build, :cache_serving_region)
    ]

    if Enum.all?(fields, &(&1 in [nil, ""])) do
      nil
    else
      %{
        client_origin: blank_to_nil(build.client_origin),
        expected_region: blank_to_nil(build.cache_expected_region),
        serving_region: blank_to_nil(build.cache_serving_region),
        serving_node: blank_to_nil(Map.get(build, :cache_serving_node)),
        serving_region_share: share(build),
        connected_at: connected_at_utc(Map.get(build, :cache_connected_at)),
        connected_before_build_seconds: Map.get(build, :cache_connected_before_build_seconds),
        verdict: build |> verdict() |> Atom.to_string()
      }
    end
  end

  @doc """
  A region's customer-facing name, or its id when the catalog does not know it.
  """
  def region_name(nil), do: nil

  def region_name(region_id) do
    case Regions.get(region_id) do
      %Regions{display_name: name} when is_binary(name) -> name
      _ -> region_id
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value

  defp share(%{cache_observed_requests: observed, cache_serving_region_requests: requests})
       when is_integer(observed) and observed > 0 and is_integer(requests) do
    Float.round(requests / observed, 3)
  end

  defp share(_build), do: nil

  defp connected_at_utc(%NaiveDateTime{} = connected_at), do: DateTime.from_naive!(connected_at, "Etc/UTC")
  defp connected_at_utc(%DateTime{} = connected_at), do: connected_at
  defp connected_at_utc(_connected_at), do: nil

  defp comparable?(region_id) do
    case Regions.get(region_id) do
      %Regions{} = region -> not Regions.private?(region)
      nil -> false
    end
  end

  defp count(value) when is_integer(value) and value >= 0, do: min(value, 4_294_967_295)
  defp count(_value), do: 0

  defp optional_count(value) when is_integer(value) and value >= 0, do: count(value)
  defp optional_count(_value), do: nil

  defp connected_at(value) when is_binary(value) do
    case NaiveDateTime.from_iso8601(value) do
      {:ok, datetime} -> datetime
      {:error, _} -> nil
    end
  end

  defp connected_at(_value), do: nil
end
