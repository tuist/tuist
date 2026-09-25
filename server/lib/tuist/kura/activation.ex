defmodule Tuist.Kura.Activation do
  @moduledoc """
  Authenticates the shared wildcard gateway's first cache request and starts
  managed capacity immediately. Only regional managed URLs leave this boundary;
  the original request is still authorized by Kura before accessing artifacts.
  """
  alias Tuist.Billing
  alias Tuist.Environment
  alias Tuist.Kura
  alias Tuist.Kura.Demand
  alias Tuist.Kura.Identity
  alias Tuist.Kura.Origins
  alias Tuist.Kura.PlacerRegions
  alias Tuist.Kura.Regions
  alias Tuist.Kura.Registrations
  alias Tuist.Kura.StableEndpoint
  alias Tuist.Kura.Workers.ProvisionOnDemandWorker
  alias Tuist.OAuth.Introspection

  def resolve(host, token) when is_binary(host) and is_binary(token) do
    with true <- Environment.tuist_hosted?(),
         {:ok, handle} <- account_handle(host),
         account when not is_nil(account) <- Identity.account_for_handle(handle),
         true <- handle in Identity.client_handles(account),
         {:authenticated, %{active: true} = identity} <- {:authenticated, Introspection.token_response(token)},
         %{active: true, cache_grants: grants} <- Introspection.token_response(token, account),
         true <- has_grants?(grants) do
      activate(account, identity)
    else
      {:authenticated, _} -> {:error, :unauthorized}
      _ -> {:error, :forbidden}
    end
  end

  def resolve(_host, _token), do: {:error, :unauthorized}

  defp activate(account, identity) do
    cond do
      Billing.cache_access_blocked?(account) -> {:error, :payment_required}
      account.custom_cache_endpoints_enabled or Registrations.list_endpoints(account) != [] -> {:error, :conflict}
      true -> route(account, Origins.value(Map.get(identity, :cache_origin)))
    end
  end

  defp route(account, origin) do
    servers = Kura.managed_cache_endpoints(account, origin)
    desired = PlacerRegions.serving_regions(account)
    host = StableEndpoint.host(account)
    endpoints = Enum.filter(servers, &eligible?(&1, desired, host))
    kick? = servers == [] and Demand.instance_expected?(account) and Demand.claim_provision_kick(account.id)
    Demand.record(account.id, origin, persist_origin: kick?)
    if kick?, do: {:ok, _job} = ProvisionOnDemandWorker.enqueue(account)

    case endpoints do
      [%{url: url} | _] when is_binary(url) -> {:ok, url}
      _ -> :pending
    end
  end

  defp eligible?(server, desired, host) do
    server.move_phase == :none and server.region in desired and
      StableEndpoint.supported?(Regions.get(server.region)) and StableEndpoint.ready?(server, host)
  end

  defp account_handle(host) do
    suffix =
      case Environment.env() do
        :prod -> ".cache.tuist.dev"
        :can -> "-canary.cache.tuist.dev"
        :stag -> "-staging.cache.tuist.dev"
        _ -> nil
      end

    if suffix && String.ends_with?(host, suffix) do
      handle = String.replace_suffix(host, suffix, "")

      if Regex.match?(~r/\A[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?\z/, handle) and
           not StableEndpoint.reserved_handle?(handle) do
        {:ok, handle}
      else
        :error
      end
    else
      :error
    end
  end

  defp has_grants?(grants) do
    Enum.any?(["account", "project"], fn kind ->
      Enum.any?(["read", "write"], &(get_in(grants, [kind, &1]) not in [nil, []]))
    end)
  end
end
