defmodule Tuist.Sandboxes.AmpReconciler do
  @moduledoc "Durable reconciliation of account-owned Amp provider workloads."
  use Oban.Worker,
    queue: :default,
    max_attempts: 5,
    unique: [period: 55, keys: [:account_id], states: [:available, :scheduled, :retryable]]

  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AmpIntegration
  alias Tuist.Sandboxes.AmpIntegrations
  alias Tuist.Sandboxes.AmpRuntime
  alias Tuist.Sandboxes.Sandbox

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    config = Environment.amp_provider_config()

    if is_binary(config.image) and is_binary(config.url) do
      case args do
        %{"account_id" => account_id} -> reconcile(account_id, config)
        _ -> sweep(config)
      end
    else
      :ok
    end
  end

  def reconcile(account_id, config) do
    AmpIntegrations.with_lock(account_id, fn -> reconcile_locked(account_id, config) end)
  end

  defp reconcile_locked(account_id, config) do
    account = Repo.get(Account, account_id)
    integration = Repo.get_by(AmpIntegration, account_id: account_id)

    if account && integration do
      enabled = integration.enabled && FeatureFlags.sandboxes_enabled?(account)
      status = reconcile_status(integration, config, enabled)

      integration
      |> Ecto.Changeset.change(status: status, last_checked_at: DateTime.utc_now(:second))
      |> Repo.update!()
    end

    :ok
  end

  defp reconcile_status(integration, config, enabled) do
    with :ok <- remove_stale(integration, config, enabled),
         :ok <- settle(integration, config, enabled) do
      observed_status(integration, config, enabled)
    else
      _ -> :error
    end
  end

  defp observed_status(integration, config, true), do: AmpRuntime.status(integration, config)
  defp observed_status(%{enabled: true}, _config, false), do: :suspended
  defp observed_status(_integration, _config, false), do: :disconnected

  defp settle(integration, config, true), do: AmpRuntime.ensure(integration, config)

  defp settle(integration, _config, false) do
    from(s in Sandbox, where: s.amp_integration_id == ^integration.id and s.state != :deleted)
    |> Repo.all()
    |> Enum.reduce_while(:ok, fn sandbox, :ok ->
      result = if sandbox.state == :paused, do: {:ok, sandbox}, else: Sandboxes.pause(sandbox)

      with {:ok, paused} <- result, {:ok, _} <- Sandboxes.end_residency(paused) do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :pause_failed}}
      end
    end)
  end

  defp remove_stale(integration, config, enabled) do
    with {:ok, items} <- AmpRuntime.resources(config, integration.id) do
      Enum.reduce_while(items, :ok, fn %{"metadata" => %{"name" => name}}, :ok ->
        if enabled && name == AmpRuntime.name(integration) do
          {:cont, :ok}
        else
          remove_resource(config.namespace, name)
        end
      end)
    end
  end

  defp sweep(config) do
    # Only IDs are loaded here: encrypted provider secrets never enter job arguments.
    integrations = Repo.all(from i in AmpIntegration, select: {i.id, i.account_id})
    Enum.each(integrations, fn {_id, account_id} -> Oban.insert!(new(%{"account_id" => account_id})) end)

    with {:ok, items} <- AmpRuntime.resources(config) do
      Enum.reduce_while(items, :ok, fn %{"metadata" => %{"name" => name, "labels" => labels}}, :ok ->
        if Repo.exists?(from i in AmpIntegration, where: i.id == ^labels["tuist.dev/amp-integration"]) do
          {:cont, :ok}
        else
          remove_resource(config.namespace, name)
        end
      end)
    end
  end

  defp remove_resource(namespace, name) do
    case AmpRuntime.remove(namespace, name) do
      :ok -> {:cont, :ok}
      error -> {:halt, error}
    end
  end
end
