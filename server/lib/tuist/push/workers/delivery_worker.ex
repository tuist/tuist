defmodule Tuist.Push.Workers.DeliveryWorker do
  @moduledoc """
  Sends one notification to one registration through APNs. The token is read
  from the registration when the job runs, so a device that unregistered or was
  retired in the meantime is skipped. A token APNs no longer accepts retires the
  registration.
  """

  use Oban.Worker, queue: :push, max_attempts: 5

  alias Tuist.Push
  alias Tuist.Push.APNs
  alias Tuist.Push.Installation
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"registration_id" => registration_id, "payload" => payload}}) do
    case Repo.get(Installation, registration_id) do
      %Installation{retired_at: nil, platform: "ios", token: token} = installation when is_binary(token) ->
        installation.environment |> APNs.deliver(token, payload) |> handle(installation)

      _ ->
        :ok
    end
  end

  defp handle(:ok, _installation), do: :ok

  defp handle({:error, :invalid_token}, installation) do
    Push.retire_rejected(installation)
    :ok
  end

  defp handle({:error, {:retry, reason}}, _installation), do: {:error, reason}

  defp handle({:error, {:rejected, reason}}, installation) do
    Logger.warning("APNs rejected a notification to #{installation.id} (#{installation.environment}): #{reason}")
    {:cancel, reason}
  end
end
