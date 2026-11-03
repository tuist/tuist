defmodule Atlas.Environments.ProviderWorker do
  @moduledoc false
  use Oban.Worker, queue: :environments, max_attempts: 5

  import Ecto.Query

  alias Atlas.Audit
  alias Atlas.Environments.Command
  alias Atlas.Environments.Commands
  alias Atlas.Environments.Environment
  alias Atlas.Environments.Provider
  alias Atlas.Orbit
  alias Atlas.Repo
  alias Atlas.Users.User

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(15)

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"environment_id" => id, "command_id" => command_id}}) do
    environment = Repo.get!(Environment, id)
    user = Repo.get!(User, environment.owner_id)
    command = Repo.get!(Command, command_id)

    with {:ok, config} <- Provider.fetch(environment.provider),
         {:ok, %{command: claimed}} <-
           Commands.claim(user, environment.oauth_client_id, id, command.id, %{"digest" => command.digest}) do
      # A durable claim precedes the external effect. A timeout, crash or failed
      # result write must never turn this job into another execution attempt.
      payload = Map.take(claimed, [:id, :tool, :arguments, :execution_timeout_seconds])

      case config.module.execute(config, Provider.identity(environment), payload) do
        {:ok, %{success: success, output: output}} ->
          Commands.complete(user, environment.oauth_client_id, id, command.id, %{
            "claim_token" => claimed.claim_token,
            "success" => success,
            "output" => output
          })

          :ok

        {:error, _} ->
          :ok
      end
    else
      {:error, _} -> :ok
    end
  end

  def perform(%Oban.Job{args: %{"environment_id" => id}}) do
    case Repo.get(Environment, id) do
      nil -> :ok
      environment -> reconcile(environment)
    end
  end

  defp reconcile(environment) do
    operation = if environment.enabled, do: :start, else: :stop

    result =
      with {:ok, config} <- Provider.fetch(environment.provider),
           do: apply(config.module, operation, [config, Provider.identity(environment)])

    state =
      case result do
        {:ok, _} -> if environment.enabled, do: "ready", else: "paused"
        _ -> "error"
      end

    Repo.update_all(from(e in Environment, where: e.id == ^environment.id and e.version == ^environment.version),
      set: [provider_state: state, updated_at: DateTime.utc_now()]
    )

    Audit.record("environment.provider_#{state}", %{
      actor_id: environment.owner_id,
      interface: "worker",
      target_type: "personal_environment",
      target_id: environment.id
    })

    Orbit.notify_changed(environment.managed_thread_id)

    case result do
      {:ok, _} -> :ok
      _ -> {:error, :environment_provider_unavailable}
    end
  end
end
