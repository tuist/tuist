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
  alias Tuist.Kura.StableEndpoint
  alias Tuist.Kura.Workers.ProvisionOnDemandWorker
  alias Tuist.OAuth.Introspection

  def resolve(host, token) when is_binary(host) and is_binary(token) do
    with true <- Environment.tuist_hosted?(),
         {:ok, handle} <- account_handle(host),
         account when not is_nil(account) <- Identity.account_for_handle(handle),
         true <- handle in Identity.client_handles(account),
         %{active: true, cache_grants: grants} <- Introspection.token_response(token, account),
         true <- has_grants?(grants) do
      if Billing.cache_access_blocked?(account) do
        {:error, :payment_required}
      else
        endpoints = Kura.managed_cache_endpoints(account)
        kick? = endpoints == [] and Demand.instance_expected?(account) and Demand.claim_provision_kick(account.id)
        Demand.record(account.id)
        if kick?, do: {:ok, _job} = ProvisionOnDemandWorker.enqueue(account)

        case endpoints do
          [%{url: url} | _] when is_binary(url) -> {:ok, url}
          _ -> :pending
        end
      end
    else
      _ -> {:error, :forbidden}
    end
  end

  def resolve(_host, _token), do: {:error, :unauthorized}

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
