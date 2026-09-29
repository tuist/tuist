defmodule Tuist.Builds.CacheRegion do
  @moduledoc """
  Where a build came from and which cache region should have served it.

  A managed account's stable hostname (`<handle>.cache.tuist.dev`) is routed by
  latency records the client's own resolver picks, so a VPN or a corporate
  resolver can send a build to a region far from where the machine is. Builds
  record three labels so that shows up:

    * `client_origin`: the Cloudflare-derived label
      (`TuistWeb.RemoteIp.origin/1`) of the request that uploaded the build,
      the same label `/api/cache/endpoints` resolves regions from.
    * `cache_expected_region`: the account's serving managed region nearest
      that origin (`Tuist.Kura.managed_cache_endpoints/2`).
    * `cache_serving_region`: the region Kura named on the responses the CAS
      proxy recorded for the build, read from the build archive.

  Region and origin labels only: no addresses.

  The expected region is what placement considers nearest (`Tuist.Kura.OriginMap`),
  not what Route53 answers. Route53 routes by the AWS latency region each
  Kura region is mapped to, and the two can disagree near zone borders: Mexico
  is in the map's South America zone, so an account serving from `sa-west` and
  `us-central` expects `sa-west` there while latency routing may answer
  `us-central`. A mismatch on such an origin is not necessarily a misrouted
  network, so read mismatches by how often they recur for an origin rather
  than one build at a time.
  """

  alias Tuist.Accounts.Account
  alias Tuist.Kura

  @doc """
  The client origin and the region expected to serve it, as build attributes.
  Both are empty for an unattributed request, and the expected region is empty
  for an account with no serving managed region.
  """
  def client_attrs(%Account{} = account, origin) when is_binary(origin) and origin != "" do
    expected =
      case Kura.managed_cache_endpoints(account, origin) do
        [%{region: region} | _] -> region
        [] -> ""
      end

    %{client_origin: origin, cache_expected_region: expected}
  end

  def client_attrs(_account, _origin), do: %{client_origin: "", cache_expected_region: ""}
end
