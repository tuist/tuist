defmodule Tuist.Push.Workers.DeliveryWorker do
  @moduledoc """
  Sends one notification to one registration, through APNs for iOS and macOS
  (on the topic of the registration's app) and FCM for Android. The token is read
  from the registration when the job runs, so a device that unregistered or was
  retired in the meantime is skipped. A token the provider no longer accepts
  retires the registration.
  """

  use Oban.Worker, queue: :push, max_attempts: 5

  alias Tuist.Push
  alias Tuist.Push.APNs
  alias Tuist.Push.FCM
  alias Tuist.Push.Installation
  alias Tuist.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"oauth_grant_id" => grant, "registration_id" => id} = args}) do
    # Generic delegated dispatch is fenced to the sign-in that accepted it.
    # A queued job cannot follow a device rebound to another session.
    case Repo.get(Installation, id) do
      %Installation{app: "luft", retired_at: nil, oauth_grant_id: ^grant} = installation ->
        if Push.grant_active?("luft", grant, installation.user_id),
          do: deliver(installation, args["payload"]),
          else: :ok

      _ ->
        :ok
    end
  end

  def perform(%Oban.Job{args: %{"registration_id" => registration_id, "payload" => payload}}) do
    deliver(Repo.get(Installation, registration_id), payload)
  end

  defp deliver(installation, payload) do
    case installation do
      %Installation{retired_at: nil, platform: platform, token: token} = installation
      when platform in ["ios", "macos"] and is_binary(token) ->
        installation.environment |> APNs.deliver(token, payload, Push.apns_topic(installation)) |> handle(installation)

      %Installation{retired_at: nil, platform: "android", token: token} = installation when is_binary(token) ->
        token |> FCM.deliver(payload) |> handle(installation)

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
    Logger.warning(
      "#{installation.platform} push rejected for #{installation.id} (#{installation.environment}): #{reason}"
    )

    {:cancel, reason}
  end
end
