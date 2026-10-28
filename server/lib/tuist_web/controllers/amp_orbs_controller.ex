defmodule TuistWeb.AmpOrbsController do
  @moduledoc false
  use TuistWeb, :controller

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Kubernetes.Client
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpIntegration
  alias Tuist.Sandboxes.AmpIntegrations
  alias Tuist.Sandboxes.AmpRuntime

  def dispatch(conn, %{"orb_id" => orb_id} = params) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, %{namespace: namespace, name: name}} <- Client.create_amp_provider_token_review(token),
         true <- namespace == Environment.amp_provider_config().namespace,
         {:ok, attrs} <- job(orb_id, params),
         {:ok, integration_id} <- integration_id(name),
         %AmpIntegration{} = integration <- Repo.get(AmpIntegration, integration_id) do
      result =
        AmpIntegrations.with_lock(integration.account_id, fn -> dispatch_bound(integration, name, orb_id, attrs) end)

      case result do
        {:ok, _} ->
          send_resp(conn, :no_content, "")

        {:error, reason} when reason in [:unauthorized, :disabled] ->
          send_resp(conn, :forbidden, "Provider is not authorized")

        {:error, :locked} ->
          send_resp(conn, :conflict, "Provider operation already in progress")

        _ ->
          send_resp(conn, :service_unavailable, "Orb operation could not complete")
      end
    else
      {:error, :invalid_job} -> send_resp(conn, :bad_request, "Invalid Orb job")
      _ -> send_resp(conn, :unauthorized, "Invalid provider identity")
    end
  end

  # Read the binding again under the lock. Lifecycle writes must be visible to nodes.
  defp dispatch_bound(integration, name, orb_id, attrs) do
    account = Repo.get(Account, integration.account_id)
    current = Repo.get(AmpIntegration, integration.id)

    cond do
      is_nil(account) or is_nil(current) or not current.enabled or AmpRuntime.name(current) != name ->
        {:error, :unauthorized}

      attrs.operation == "spawn" and not FeatureFlags.sandboxes_enabled?(account) ->
        {:error, :disabled}

      true ->
        Sandboxes.dispatch_amp_orb(account, orb_id, Map.put(attrs, :amp_integration_id, current.id))
    end
  end

  defp integration_id("amp-" <> rest) do
    case String.split(rest, "-") do
      [hex, revision] when byte_size(hex) == 32 and byte_size(revision) <= 10 ->
        with {:ok, raw} <- Base.decode16(hex, case: :lower), do: Ecto.UUID.load(raw)

      _ ->
        {:error, :invalid_identity}
    end
  end

  defp integration_id(_), do: {:error, :invalid_identity}

  defp job(orb_id, params) when byte_size(orb_id) in 1..255 do
    operation = params["operation"]
    token = params["orb_token"]

    if Regex.match?(~r/^[a-zA-Z0-9_-]+$/, orb_id) and operation in ["spawn", "pause", "delete"] and
         (operation != "spawn" or (is_binary(token) and byte_size(token) in 1..16_384)) do
      # Managed connections have a server-selected template/shape and Amp origin.
      # Neither workload credentials nor client params grant arbitrary guest exec.
      {:ok, %{operation: operation, orb_token: token, template: "default", vcpus: 2, memory_mb: 4096, workspace_gb: 10}}
    else
      {:error, :invalid_job}
    end
  end

  defp job(_, _), do: {:error, :invalid_job}
end
