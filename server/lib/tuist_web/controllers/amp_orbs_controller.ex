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

      respond(conn, result)
    else
      {:error, :unknown_orb_type} ->
        conn
        |> put_resp_header("x-tuist-orb-refusal", "unknown-orb-type")
        |> send_resp(:bad_request, "Unknown orb type")

      {:error, :invalid_job} ->
        send_resp(conn, :bad_request, "Invalid Orb job")

      _ ->
        send_resp(conn, :unauthorized, "Invalid provider identity")
    end
  end

  defp respond(conn, {:ok, _}) do
    send_resp(conn, :no_content, "")
  end

  defp respond(conn, {:error, reason}) when reason in [:unauthorized, :disabled] do
    send_resp(conn, :forbidden, "Provider is not authorized")
  end

  defp respond(conn, {:error, :sandbox_concurrency_limit}) do
    conn
    |> put_resp_header("x-tuist-orb-retry", "admission")
    |> send_resp(:too_many_requests, "Account sandbox CPU or memory limit reached")
  end

  # An archive of the account's oldest paused Orb is on its way.
  defp respond(conn, {:error, :sandbox_disk_limit}) do
    conn
    |> put_resp_header("x-tuist-orb-retry", "admission")
    |> send_resp(:too_many_requests, "Account sandbox disk limit reached; archiving a paused Orb")
  end

  # Nothing can be archived (archiving off, the account at its archive
  # storage cap, or no paused Orb), so waiting is not enough; deleting
  # Orbs is.
  defp respond(conn, {:error, :sandbox_limit}) do
    conn
    |> put_resp_header("x-tuist-orb-refusal", "sandbox-limit")
    |> send_resp(:too_many_requests, "Account sandbox disk limit reached")
  end

  defp respond(conn, {:error, reason}) when reason in [:locked, :sandbox_account_busy] do
    conn
    |> put_resp_header("x-tuist-orb-retry", "admission")
    |> send_resp(:conflict, "Provider operation already in progress")
  end

  defp respond(conn, {:error, :no_capacity}) do
    conn
    |> put_resp_header("x-tuist-orb-retry", "admission")
    |> send_resp(:service_unavailable, "No sandbox capacity available")
  end

  defp respond(conn, {:error, :orb_type_mismatch}) do
    conn
    |> put_resp_header("x-tuist-orb-refusal", "orb-type-mismatch")
    |> send_resp(:conflict, "The Orb exists on another platform than its orb type")
  end

  defp respond(conn, _result) do
    send_resp(conn, :service_unavailable, "Orb operation could not complete")
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
    snapshot_id = params["snapshot_id"]

    if Regex.match?(~r/^[a-zA-Z0-9_-]+$/, orb_id) and operation in ["spawn", "pause", "delete"] and
         (operation != "spawn" or (is_binary(token) and byte_size(token) in 1..16_384)) and
         valid_snapshot_id?(snapshot_id) do
      # Managed connections take their template and shape from the server's
      # orb type catalog and their Amp origin from the server. Neither workload
      # credentials nor client params grant arbitrary guest exec. Pause and
      # delete act on the existing row, so only a spawn reads the type.
      with {:ok, shape} <- spawn_shape(operation, params["orb_type"]) do
        {:ok, Map.merge(%{operation: operation, orb_token: token, snapshot_id: snapshot_id}, shape)}
      end
    else
      {:error, :invalid_job}
    end
  end

  defp job(_, _), do: {:error, :invalid_job}

  defp spawn_shape("spawn", orb_type) when is_nil(orb_type) or is_binary(orb_type), do: Sandboxes.amp_orb_type(orb_type)
  defp spawn_shape("spawn", _orb_type), do: {:error, :invalid_job}
  defp spawn_shape(_operation, _orb_type), do: {:ok, %{}}

  defp valid_snapshot_id?(nil), do: true

  defp valid_snapshot_id?(snapshot_id) when is_binary(snapshot_id),
    do: Regex.match?(~r/^[A-Za-z0-9._:-]{1,255}$/, snapshot_id)

  defp valid_snapshot_id?(_snapshot_id), do: false
end
