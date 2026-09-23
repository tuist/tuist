defmodule Tuist.Kura.StableEndpoint do
  @moduledoc """
  Managed cache hostname intent and readiness. Rendering and hand-out are
  independent switches. Readiness is a shared, freshness-bounded projection of
  controller observations; endpoint requests never call Kubernetes or AWS.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Provisioner.KubernetesController
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Server
  alias Tuist.Repo

  require Logger

  @freshness_seconds 180

  def host(%Account{name: name}) do
    suffix =
      case Environment.env() do
        :prod -> ""
        :stag -> "-staging"
        :can -> "-canary"
        _ -> nil
      end

    if suffix != nil and not reserved_handle?(name), do: "#{String.downcase(name)}#{suffix}.cache.tuist.dev"
  end

  def reserved_handle?(name), do: String.ends_with?(String.downcase(name), ["-staging", "-canary"])

  def supported?(%Regions{provisioner_config: config} = region) do
    not Regions.private?(region) and is_binary(config[:aws_region]) and config[:gateway] == :host_network
  end

  def supported?(_), do: false

  def enabled_for_account?(account) do
    allowed = Environment.kura_stable_hostname_accounts()

    Environment.kura_stable_hostname_enabled?() and
      (allowed == [] or String.downcase(account.name) in allowed) and
      FeatureFlags.kura_stable_hostname_enabled?(account)
  end

  def intent(server, region, claimed \\ nil)

  def intent(%Server{account: account} = server, region, claimed) do
    enabled = enabled_for_account?(account) and supported?(region) and server.move_phase == :none
    claimed = if enabled, do: claimed || PlacerRegions.claimed_regions(account), else: []
    stable_host = if server.region in claimed, do: host(account)

    %{
      "stableHost" => stable_host || "",
      "stableAWSRegion" => if(stable_host, do: region.provisioner_config.aws_region, else: ""),
      "stableAdvertise" => not is_nil(stable_host) and server.status == :active
    }
  end

  # Include draining rows: the ordinary image reconciler intentionally skips
  # them, but withdrawal is the first part of a drain, not its final deletion.
  def reconcile do
    servers =
      Server
      |> where([s], s.status in [:provisioning, :replicating, :active, :failed, :drain_pending])
      |> where([s], s.move_phase == :none and not is_nil(s.provisioner_node_ref))
      |> preload(:account)
      |> Repo.all()

    claimed = servers |> Enum.map(& &1.account) |> PlacerRegions.claimed_regions_all()

    Enum.each(servers, fn server ->
      region = Regions.get(server.region)

      if supported?(region) do
        case KubernetesController.sync_stable_endpoint(server, region, Map.get(claimed, server.account_id, [])) do
          {:error, reason} ->
            Logger.warning("[Kura.StableEndpoint] could not synchronize #{server.id}: #{inspect(reason)}")

          _ ->
            :ok
        end
      end
    end)
  end

  def observe(region, name, instance) do
    status = get_in(instance, ["status", "stableEndpoint"]) || %{}
    spec = instance["spec"] || %{}

    ready =
      status["ready"] == true and spec["stableAdvertise"] == true and
        status["host"] == spec["stableHost"] and
        status["observedGeneration"] == get_in(instance, ["metadata", "generation"])

    projection = %{"host" => status["host"], "checked_at" => status["lastCheckedAt"], "ready" => ready}

    Server
    |> where([s], s.region == ^region and s.provisioner_node_ref == ^name)
    |> where([s], s.status in [:provisioning, :replicating, :active, :failed, :drain_pending])
    |> Repo.update_all(set: [stable_endpoint: projection])
  end

  def ready?(%Server{stable_endpoint: projection}, expected_host) do
    with %{"ready" => true, "host" => ^expected_host, "checked_at" => checked_at} <- projection,
         true <- is_binary(checked_at),
         {:ok, checked, _} <- DateTime.from_iso8601(checked_at),
         age when age >= 0 and age <= @freshness_seconds <- DateTime.diff(DateTime.utc_now(), checked) do
      true
    else
      _ -> false
    end
  end

  def retirement_ready?(server, account) do
    stable_host = host(account)

    if enabled_for_account?(account) and stable_host != nil and supported?(Regions.get(server.region)) do
      ready?(server, stable_host)
    else
      true
    end
  end

  def resolve(account, regional_urls) do
    if regional_urls != [] and enabled_for_account?(account) and
         Environment.kura_stable_hostname_handout_enabled?() do
      resolve_ready(account, regional_urls)
    else
      regional_urls
    end
  end

  defp resolve_ready(account, regional_urls) do
    desired = PlacerRegions.serving_regions(account)

    servers =
      Repo.all(from s in Server, where: s.account_id == ^account.id and s.status == :active and s.move_phase == :none)

    host = host(account)
    managed = Enum.filter(servers, &supported?(Regions.get(&1.region)))
    serving = Enum.filter(managed, &(&1.region in desired))

    all_ready =
      host != nil and serving != [] and Enum.all?(managed, &ready?(&1, host)) and
        Enum.all?(desired, fn region -> Enum.any?(serving, &(&1.region == region and ready?(&1, host))) end)

    if all_ready do
      managed_urls = Enum.map(managed, & &1.url)
      Enum.uniq(["https://#{host}" | regional_urls -- managed_urls])
    else
      regional_urls
    end
  end
end
